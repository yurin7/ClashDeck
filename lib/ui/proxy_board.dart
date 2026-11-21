import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/edit/group_selection.dart';
import '../core/edit/group_status.dart';
import '../core/edit/member_picker.dart';
import '../core/model/profile.dart';
import '../core/schema/group_schema.dart';
import '../core/yaml/yaml_doc.dart';
import '../runtime/runtime_controller.dart';
import '../state/editor_state.dart';
import 'import_dialogs.dart';
import 'dropdown.dart';
import 'fields.dart';
import 'motion.dart';
import 'rules/group_rules_block.dart';
import 'rule_picker_sheet.dart';
import 'chips.dart';
import 'sheets.dart';
import 'sheets/node_picker_sheet.dart';
import 'theme.dart';
import 'widgets/delete_confirm.dart';
import 'widgets/delay_badge.dart';
import 'widgets/drag_rules.dart';
import 'widgets/drag_state.dart';
import 'widgets/edit_dialog.dart';
import 'widgets/node_row.dart';
import 'widgets/relay_chain.dart';
import 'widgets/selectable_tile.dart';
import 'widgets.dart';
import 'node_form_page.dart';
import 'navigation.dart';
import './widgets/select_sheet.dart';

/// 「添加节点」的三种入口。
enum _AddMode { manual, links, subscription }

/// 按策略组组织的节点面板：跨组拖拽、增删节点、改组成员。
class ProxyBoard extends StatefulWidget {
  const ProxyBoard({
    super.key,
    required this.state,
    this.onSubscriptionSaved,
    this.runtime,
    this.isActiveProfile = true,
    this.groupSelection = const <String, String>{},
    this.onGroupSelection,
    this.cachedDelays = const <String, int?>{},
  });

  final EditorState state;

  /// 用户导入/记下订阅地址时回调（编辑器用它把地址写进 sidecar meta）。
  final Future<void> Function(String url)? onSubscriptionSaved;

  /// 用于测速和读取当前出口的运行控制器。
  final RuntimeController? runtime;

  /// 面板打开的是当前启用的配置。
  final bool isActiveProfile;

  /// 每个组上次选中的节点（sidecar 里记的选择）。停止状态下也用它做高亮。
  final Map<String, String> groupSelection;

  /// 点组内节点时回调：把这次选择记进当前配置的 sidecar，重开仍在。
  final Future<void> Function(String group, String node)? onGroupSelection;

  /// 上次测速缓存（毫秒；null 表示超时），用于节点行副标题。
  final Map<String, int?> cachedDelays;

  @override
  State<ProxyBoard> createState() => _ProxyBoardState();
}

class _ProxyBoardState extends State<ProxyBoard>
    with SingleTickerProviderStateMixin {
  EditorState get s => widget.state;

  RuntimeController? get _selectionRuntime {
    final runtime = widget.runtime;
    return widget.isActiveProfile && runtime?.phase == RuntimePhase.running
        ? runtime
        : null;
  }

  /// 当前左滑露出「删除」的组名。
  String? _swipedGroup;

  /// 手动测速进行中（禁用入口并显示进度）。
  bool _testing = false;
  int _testDone = 0;
  int _testTotal = 0;

  /// 非法拖拽松手后的「滑回原位」动画。
  late final AnimationController _snapBack;
  OverlayEntry? _snapEntry;
  DragSnapBack? _snap;

  @override
  void initState() {
    super.initState();
    _snapBack =
        AnimationController(vsync: this, duration: Motion.normal.snapBack)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) _finishSnapBack();
          });
    dragState.addListener(_onDragStateChanged);
  }

  @override
  void dispose() {
    dragState.removeListener(_onDragStateChanged);
    _snapEntry?.remove();
    _snapEntry = null;
    _snapBack.dispose();
    super.dispose();
  }

  void _onDragStateChanged() {
    if (dragState.dragging || dragState.animating) return;
    final snap = dragState.takeSnapBack();
    if (snap == null) return;
    _playSnapBack(snap);
  }

  void _playSnapBack(DragSnapBack snap) {
    final profile = s.profile;
    final node = profile.proxy(snap.member);
    final group = profile.group(snap.member);
    final Widget chip;
    if (node != null) {
      final runtime = widget.runtime;
      final delay = runtime?.delays[snap.member];
      chip = NodeChip(
        node: node,
        fromGroup: snap.fromGroup,
        onOpen: () {},
        onMove: () {},
        onDelete: () {},
        onRemove: null,
        draggable: false,
        delayText: delay == null
            ? null
            : formatDelay(delay, approx: runtime!.delayApprox(snap.member)),
      );
    } else if (group != null) {
      chip = GroupChip(
        name: group.name,
        members: group.members.length,
        type: group.type,
      );
    } else {
      dragState.finishSnapBack();
      return;
    }
    _snap = snap;
    final overlay = Overlay.of(context);
    final entry = OverlayEntry(
      builder: (context) => AnimatedBuilder(
        animation: _snapBack,
        builder: (context, child) {
          final t = Curves.easeOutCubic.transform(_snapBack.value);
          final topLeft = Offset.lerp(
            snap.endOffset,
            snap.sourceRect.topLeft,
            t,
          )!;
          return Positioned(
            left: topLeft.dx,
            top: topLeft.dy,
            width: snap.feedbackSize.width,
            height: snap.feedbackSize.height,
            child: IgnorePointer(
              child: Opacity(
                opacity: 1 - 0.7 * t,
                child: Transform.scale(
                  scale: 1 - 0.04 * t,
                  alignment: Alignment.center,
                  child: child,
                ),
              ),
            ),
          );
        },
        child: Material(color: Colors.transparent, child: chip),
      ),
    );
    _snapEntry = entry;
    overlay.insert(entry);
    _snapBack.forward(from: 0);
  }

  void _finishSnapBack() {
    final duplicate = _snap?.duplicateGroup;
    _snapEntry?.remove();
    _snapEntry = null;
    _snap = null;
    dragState.finishSnapBack();
    if (!mounted) return;
    if (duplicate != null) {
      _toast('该成员已在「$duplicate」里');
    }
  }

  Future<void> _testNodes(List<String> names) async {
    final runtime = widget.runtime;
    if (runtime == null || names.isEmpty) return;
    if (_testing) return;
    setState(() {
      _testing = true;
      _testDone = 0;
      _testTotal = names.length;
    });
    try {
      await runtime.testDelays(
        names,
        onProgress: (done, total) {
          if (!mounted) return;
          setState(() {
            _testDone = done;
            _testTotal = total;
          });
        },
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
    if (!mounted) return;
    final approx = names.any(runtime.delayApprox);
    _toast(
      approx
          ? '测速完成：${names.length} 个节点（≈ 为 TCP 近似值）'
          : '测速完成：${names.length} 个节点',
    );
  }

  void _fail() {
    final msg = s.lastError;
    if (msg == null) return;
    showToast(context, msg);
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _addNode() async {
    final mode = await showAppSheet<_AddMode>(
      context,
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('手动填写'),
            subtitle: const Text('按协议 schema 一项项填，字段跟着协议变'),
            onTap: () => Navigator.pop(ctx, _AddMode.manual),
          ),
          ListTile(
            leading: const Icon(Icons.link),
            title: const Text('粘贴分享链接'),
            subtitle: const Text('vless / vmess / trojan / ss / hy2 …，可以一次粘多条'),
            onTap: () => Navigator.pop(ctx, _AddMode.links),
          ),
          ListTile(
            leading: const Icon(Icons.cloud_download_outlined),
            title: const Text('从订阅链接导入'),
            subtitle: const Text('填机场订阅地址，一次把节点全拉进来'),
            onTap: () => Navigator.pop(ctx, _AddMode.subscription),
          ),
        ],
      ),
    );
    if (!mounted) return;
    switch (mode) {
      case _AddMode.manual:
        await _addNodeForm();
      case _AddMode.links:
        await _importFromLinks();
      case _AddMode.subscription:
        await _importFromSubscription();
      case null:
        return;
    }
  }

  Future<void> _addNodeForm() async {
    final profile = s.profile;
    final result = await Navigator.of(context).push<Map<String, Object?>>(
      appRoute<Map<String, Object?>>(
        NodeFormPage(existingNames: profile.proxyNames.toList()),
      ),
    );
    if (result == null || !mounted) return;
    if (!s.addProxy(result)) {
      _fail();
      return;
    }
    if (!mounted) return;
    final groups = s.profile.groups;
    if (groups.isEmpty) return;
    final target = await _pickGroup(title: '把「${result['name']}」加入哪个组？');
    if (target == null) return;
    if (!s.addGroupMember(
      target,
      '${result['name']}',
      appendToEnd: s.profile.group(target)?.type == 'relay',
    )) {
      _fail();
    }
  }

  Future<void> _importFromLinks() async {
    final text = await showPasteLinksDialog(context);
    if (text == null || text.trim().isEmpty || !mounted) return;

    final count = s.countShareLinks(text);
    if (count == 0) {
      _toast('没解析出可用的链接，检查一下格式（要带上 vless:// 这种前缀）');
      return;
    }
    final target = await _pickGroup(title: '把 $count 个节点加入哪个组？（可跳过）');
    if (!mounted) return;
    if (!s.importLinkText(text, group: target)) {
      _fail();
      return;
    }
    _toast('已导入 $count 个节点${target == null ? '' : '，加入「$target」'}');
  }

  Future<void> _importFromSubscription() async {
    final input = await showSubscriptionDialog(context);
    if (input == null || !mounted) return;
    final result = input.result;
    if (result == null) {
      _toast('订阅地址已记下：${input.url}');
      await widget.onSubscriptionSaved?.call(input.url);
      return;
    }
    final target = await _pickGroup(title: '把 ${result.count} 个节点加入哪个组？（可跳过）');
    if (!mounted) return;
    if (!s.importProxyList(result.proxies, group: target)) {
      _fail();
      return;
    }
    _toast(
      '已从订阅导入 ${result.count} 个节点'
      '${target == null ? '' : '，加入「$target」'}',
    );
    await widget.onSubscriptionSaved?.call(input.url);
  }

  void _toast(String msg) {
    if (!mounted) return;
    showToast(context, msg);
  }

  Future<void> _editNode(ProxyEntry node) async {
    final result = await Navigator.of(context).push<Map<String, Object?>>(
      appRoute<Map<String, Object?>>(
        NodeFormPage(
          initial: node.raw,
          existingNames: s.profile.proxyNames
              .where((n) => n != node.name)
              .toList(),
          // 手机上没法右键菜单，删除只能从编辑页进来；确认框已经在编辑页里问过了。
          onDelete: () async {
            if (!s.deleteProxy(node.name)) _fail();
          },
        ),
      ),
    );
    if (result == null) return;
    if (!s.apply((d) => ConfigOps.updateProxy(d, node.name, result))) _fail();
  }

  /// 组内点节点 = 把这个组当前出口改成该节点。
  ///
  /// 选择先写入当前配置的 sidecar，内核运行此配置时同步切换出口。
  Future<void> _selectNodeForGroup(String group, String name) async {
    await widget.onGroupSelection?.call(group, name);
    if (!mounted) return;
    setState(() {});
    final runtime = _selectionRuntime;
    if (runtime == null) return;
    if (s.dirty &&
        runtime.members.isNotEmpty &&
        runtime.members[group]?.contains(name) != true) {
      _toast('已记住「$name」，保存配置后切换');
      return;
    }
    final ok = await runtime.selectNode(group, name);
    if (!mounted) return;
    if (!ok) {
      _toast(runtime.lastError ?? '内核未确认切换到「$name」');
      return;
    }
    _toast('「$group」现在用 $name');
  }

  Future<void> _deleteNode(ProxyEntry node) async {
    final refs = s.profile.groups
        .where((g) => !g.computedMembers && g.members.contains(node.name))
        .map((g) => g.name)
        .toList();
    final ok = await _confirm(
      '删除节点「${node.name}」？',
      '会同时从所有策略组里移除它。',
      extraHint: refs.isEmpty
          ? null
          : '${refs.length} 个组引用了它：${refs.join('、')}。删除后会一起移除。',
    );
    if (!ok) return;
    if (!s.deleteProxy(node.name)) _fail();
  }

  /// 芯片上的 ⋮：手机上唯一稳定可达的「编辑 / 移动 / 删除」入口。
  Future<void> _showNodeActions(ProxyEntry node, {String? fromGroup}) async {
    final scheme = Theme.of(context).colorScheme;
    final action = await showAppSheet<String>(
      context,
      body: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.edit_outlined),
            title: const Text('编辑节点'),
            onTap: () => Navigator.pop(ctx, 'edit'),
          ),
          ListTile(
            leading: const Icon(Icons.drive_file_move_outline),
            title: const Text('移动到…'),
            subtitle: const Text('也可以长按芯片直接拖到目标组'),
            onTap: () => Navigator.pop(ctx, 'move'),
          ),
          if (fromGroup != null)
            ListTile(
              leading: const Icon(Icons.remove_circle_outline),
              title: Text('从「$fromGroup」移除'),
              onTap: () => Navigator.pop(ctx, 'remove'),
            ),
          ListTile(
            leading: Icon(Icons.delete_outline, color: scheme.error),
            title: Text('删除节点', style: TextStyle(color: scheme.error)),
            subtitle: const Text('会同时从所有策略组里移除'),
            onTap: () => Navigator.pop(ctx, 'delete'),
          ),
        ],
      ),
    );
    if (!mounted || action == null) return;
    switch (action) {
      case 'edit':
        await _editNode(node);
      case 'move':
        await _moveDialog(node, fromGroup);
      case 'remove':
        if (!s.removeGroupMember(fromGroup!, node.name)) _fail();
      case 'delete':
        await _deleteNode(node);
    }
  }

  Future<String?> _pickGroup({String title = '选择策略组'}) async {
    final groups = s.profile.groups;
    if (groups.isEmpty) return null;
    return showSelectSheet<String>(
      context,
      title: title,
      actions: <Widget>[
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('跳过'),
        ),
      ],
      body: (ctx) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        children: [
          for (final g in groups)
            SelectableTile(
              title: Text(g.name),
              subtitle: Text(g.typeLabel, style: hintStyle(ctx)),
              onTap: () => Navigator.pop(ctx, g.name),
            ),
        ],
      ),
    );
  }

  Future<void> _moveDialog(ProxyEntry node, String? fromGroup) async {
    final groups = s.profile.groups.where((g) => g.name != fromGroup).toList();
    if (groups.isEmpty) return;
    final target = await showSelectSheet<String>(
      context,
      title: '把「${node.name}」移动到…',
      body: (ctx) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        children: [
          for (final g in groups)
            SelectableTile(
              title: Text(g.name),
              subtitle: Text(g.typeLabel, style: hintStyle(ctx)),
              onTap: () => Navigator.pop(ctx, g.name),
            ),
        ],
      ),
    );
    if (target == null) return;
    final ok = fromGroup == null
        ? s.addGroupMember(
            target,
            node.name,
            appendToEnd: s.profile.group(target)?.type == 'relay',
          )
        : s.moveMember(node.name, fromGroup, target);
    if (!ok) _fail();
  }

  Future<void> _addGroup() async {
    final spec = await showAppDialog<_NewGroupSpec>(
      context,
      width: dialogWidthOf(context),
      builder: (_) => const _NewGroupDialog(),
    );
    if (spec == null || spec.name.isEmpty) return;
    // 成员完全由对话框里的两个勾选决定，不再按组类型隐式塞 DIRECT。
    final members = <String>[
      if (spec.withDirect) 'DIRECT',
      if (spec.withReject) 'REJECT',
    ];
    if (!s.apply(
      (d) => ConfigOps.addGroup(d, {
        'name': spec.name,
        'type': spec.type,
      }, members: members),
    )) {
      _fail();
      return;
    }
    // 新组默认把第一个成员当作当前出口：DIRECT 默认勾选，所以新建后就是高亮的。
    if (members.isNotEmpty) {
      await widget.onGroupSelection?.call(spec.name, members.first);
      if (mounted) setState(() {});
    }
  }

  Future<void> _editGroup(GroupEntry group) async {
    final result = await showAppDialog<_GroupEditResult>(
      context,
      width: dialogWidthOf(context),
      builder: (_) => _EditGroupDialog(group: group),
    );
    if (result == null) return;

    final newName = result.name.trim();
    var doc = s.doc;
    try {
      if (newName.isNotEmpty && newName != group.name) {
        doc = ConfigOps.renameGroup(doc, group.name, newName);
      }
      final changes = <String, Object?>{
        'type': result.type,
        if (result.type == 'url-test' ||
            result.type == 'fallback' ||
            result.type == 'load-balance') ...{
          'url': result.url.trim().isEmpty ? null : result.url.trim(),
          'interval': int.tryParse(result.interval.trim()),
        },
        'hidden': result.hidden ? true : null,
      };
      doc = ConfigOps.patchGroup(
        doc,
        newName.isEmpty ? group.name : newName,
        changes,
      );
      s.replaceText(doc.text);
    } on ConfigEditException catch (e) {
      s.lastError = e.message;
      _fail();
    }
  }

  static String _groupTypeLabel(String t) => switch (t) {
    'select' => '手动选择 select',
    'url-test' => '自动测速 url-test',
    'fallback' => '故障转移 fallback',
    'load-balance' => '负载均衡 load-balance',
    'relay' => '链式代理 relay',
    _ => t,
  };

  Future<bool> _confirm(String title, String message, {String? extraHint}) =>
      confirmDelete(
        context,
        title: title,
        message: message,
        extraHint: extraHint,
      );

  Future<void> _deleteGroup(GroupEntry group) async {
    final ok = await _confirm(
      '删除策略组「${group.name}」？',
      '组里的节点不会被删除；引用它的规则会变成悬空引用，校验会提示。',
    );
    if (!ok) return;
    if (!s.apply((d) => ConfigOps.deleteGroup(d, group.name))) _fail();
  }

  /// 把一条规则改挂到 [target]（「本组规则」拖到组卡时用）。
  Future<void> _retargetRule(RuleEntry rule, String target) async {
    if (rule.target == target) return;
    final ok = s.apply(
      (d) => ConfigOps.updateRule(d, rule.index, ruleWithTarget(rule, target)),
    );
    if (!ok) {
      _fail();
      return;
    }
    _toast('已把这条规则挂到「$target」');
  }
  // ---------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final runtime = widget.runtime;
    if (runtime == null) return _buildBody(context);
    // 运行期切换（点组内节点）后，RuntimeController 里 selected 变了；这里跟着重建，
    // 才能把新选中的芯片高亮出来。
    return ListenableBuilder(
      listenable: runtime,
      builder: (context, _) => _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final profile = s.profile;
    // 「自动选择」在还没有节点时不会写进 YAML，这里用虚拟卡占位；
    // 成员固定等于全部节点，由内核按 url-test 测速决定出口。
    final groups = <GroupEntry>[...profile.groups];
    if (profile.group(kAutoGroupName) == null) {
      final at = groups.indexWhere((g) => g.name == kDefaultGroupName);
      groups.insert(
        at < 0 ? 0 : at + 1,
        GroupEntry(
          index: -1,
          name: kAutoGroupName,
          type: 'url-test',
          members: [for (final proxy in profile.proxies) proxy.name],
          raw: const <String, Object?>{},
        ),
      );
    }
    final selection = groupSelectionSnapshot(profile, widget.groupSelection);
    final liveSelection = _selectionRuntime?.selected;
    if (liveSelection != null) {
      for (final group in groups) {
        final name = liveSelection[group.name];
        if (name != null && group.members.contains(name)) {
          selection[group.name] = name;
        }
      }
    }
    final approx = <String>{...?widget.runtime?.approxDelays};
    // 有节点就能测速：内核在跑走精确接口，未运行走 TCP 近似。
    // 「测速中是否可点」由卡片按 testing 统一禁用（canTestDelay 的判据）。

    return ListView(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 120),
      children: [
        SectionTitle(
          title: 'PROXIES',
          subtitle: '点行编辑，长按拖到组卡；左滑删除',
          icon: Icons.hub_outlined,
          trailing: Text(
            '${profile.proxies.length} 节点 · ${profile.groups.length} 组',
            style: mono(11, color: scheme.onSurfaceVariant, letterSpacing: 0.3),
          ),
        ),
        _NodeListCard(
          nodes: profile.proxies,
          delays: {...widget.cachedDelays, ...?widget.runtime?.delays},
          approx: approx,
          currentName: selection[kDefaultGroupName],
          onTestAll: profile.proxies.isEmpty
              ? null
              : () => _testNodes([for (final p in profile.proxies) p.name]),
          testing: _testing,
          testProgress: _testing ? '测速中 $_testDone/$_testTotal' : null,
          onOpen: _editNode,
          onDelete: _deleteNode,
          onMenuNode: (n) => _showNodeActions(n),
          onAdd: _addNode,
          onDrop: (data) {
            if (data.fromGroup == null) return;
            final ok = s.removeGroupMember(data.fromGroup!, data.name);
            if (!ok) _fail();
          },
        ),
        const SizedBox(height: Insets.md),
        _GroupsToolRow(onCreate: _addGroup),
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(top: Insets.md),
            child: _GroupCard(
              swipeOpen: _swipedGroup == group.name,
              onSwipeOpenChanged: (open) =>
                  setState(() => _swipedGroup = open ? group.name : null),
              group: group,
              isAuto: group.name == kAutoGroupName,
              state: s,
              onOpenNode: _editNode,
              onMove: (n, from) => _moveDialog(n, from),
              onDeleteNode: _deleteNode,
              onMenuNode: (n, from) => _showNodeActions(n, fromGroup: from),
              selectedName: group.name == kAutoGroupName
                  ? null
                  : selection[group.name],
              onSelectMember: group.name == kAutoGroupName
                  ? (_) => _toast('「自动选择」按测速结果自动选，不能手动切')
                  : widget.runtime == null && widget.onGroupSelection == null
                  ? null
                  : (name) => _selectNodeForGroup(group.name, name),
              onRelayInsert: (node, index) {
                final from = group.members.length;
                if (!s.addGroupMember(
                  group.name,
                  node,
                  appendToEnd: group.type == 'relay',
                )) {
                  _fail();
                  return;
                }
                if (!s.moveGroupMember(group.name, from, index)) _fail();
              },
              onRelayReorder: (from, to) {
                if (!s.moveGroupMember(group.name, from, to)) _fail();
              },
              onEdit: () => _editGroup(group),
              onDelete: () => _deleteGroup(group),
              onTestGroup: group.members.isEmpty
                  ? null
                  : () => _testNodes([...group.members]),
              testing: _testing,
              delays: {...widget.cachedDelays, ...?widget.runtime?.delays},
              approx: approx,
              onAddMember: () async {
                final picked = await _pickMembers(profile, group);
                if (picked == null || picked.isEmpty) return;
                final names = group.type == 'relay'
                    ? orderNamesByNodeList(
                        profile,
                        picked.where(profile.proxyByName.containsKey),
                      )
                    : picked;
                if (names.isEmpty) {
                  _toast('链式代理只能添加节点');
                  return;
                }
                var added = 0;
                for (final name in names) {
                  if (s.addGroupMember(
                    group.name,
                    name,
                    appendToEnd: group.type == 'relay',
                  )) {
                    added++;
                  }
                }
                if (added == 0) {
                  _fail();
                  return;
                }
                // 组头计数直接读 state，刷新一次就能看到新成员。
                if (mounted) {
                  setState(() {});
                  _toast('已加入 $added 个');
                }
              },
              onDrop: (data) async {
                final name = data.name;
                final ok = data.fromGroup == null
                    ? s.addGroupMember(
                        group.name,
                        name,
                        appendToEnd: group.type == 'relay',
                      )
                    : s.moveMember(name, data.fromGroup!, group.name);
                if (!ok) {
                  _fail();
                  return;
                }
                final runtime = _selectionRuntime;
                await _selectNodeForGroup(group.name, name);
                if (mounted && runtime == null) {
                  _toast('已加入并切换到「$name」');
                }
              },
              onRemove: (name) {
                if (!s.removeGroupMember(group.name, name)) _fail();
              },
              onDropRule: (rule) => _retargetRule(rule, group.name),
            ),
          ),
        // 系统策略：不进 YAML 建同名组，只在这里只读展示，但可以挂规则。
        const SizedBox(height: Insets.md),
        MicroLabel('系统策略'),
        for (final (name, subtitle) in const [
          ('DIRECT', '直连：不经过代理，直接访问目标'),
          ('REJECT', '拒绝：直接断开，不发出请求'),
        ]) ...[
          const SizedBox(height: Insets.sm),
          _SystemPolicyCard(
            state: s,
            target: name,
            subtitle: subtitle,
            onDropRule: (rule) => _retargetRule(rule, name),
          ),
        ],
        const SizedBox(height: Insets.xl),
      ],
    );
  }

  /// 「选择要加入的节点」底部弹窗。
  ///
  /// 走统一的 [showNodePickerSheet]：系统策略 → 节点 → 策略组三段、
  /// 高亮多选、全选/反选/清空，0 节点时「系统策略」段照样可选。
  Future<List<String>?> _pickMembers(Profile profile, GroupEntry group) {
    return showNodePickerSheet(
      context,
      profile: profile,
      groupName: group.name,
      members: group.members,
      // 链式代理只能填节点：系统策略和策略组选了也会被过滤掉，直接不展示。
      includeBuiltins: group.type != 'relay',
      includeGroups: group.type != 'relay',
      onCreateNode: () {
        Navigator.pop(context);
        // 和节点列表右上「+」同一个入口：先选模式，再进对应表单。
        _addNode();
      },
    );
  }
}

/// 拖拽高亮时的边框色。
Color _dropBorder(ColorScheme scheme, bool active) =>
    active ? scheme.primary : scheme.outlineVariant.withValues(alpha: 0.7);

/// 全部节点列表：默认折叠，点标题展开。
///
/// 这里列出 `proxies:` 里的所有节点，不管它有没有被加进某个策略组；
/// 从组里把芯片拖到这张卡上 = 从那个组移除（节点本身保留）。
class _NodeListCard extends StatefulWidget {
  const _NodeListCard({
    required this.nodes,
    required this.onOpen,
    required this.onDelete,
    required this.onDrop,
    required this.onAdd,
    this.onMenuNode,
    this.delays = const <String, int?>{},
    this.approx = const <String>{},
    this.currentName,
    this.onTestAll,
    this.testing = false,
    this.testProgress,
  });

  final List<ProxyEntry> nodes;
  final void Function(ProxyEntry) onOpen;
  final void Function(ProxyEntry) onDelete;
  final void Function(DragNodeData) onDrop;

  /// 区头的「添加节点」入口，和底部「新建组」并列。
  final VoidCallback onAdd;

  /// 手机上点行尾 ⋮ 打开操作表（编辑 / 移动 / 删除）。
  final void Function(ProxyEntry)? onMenuNode;

  /// 最近一次测速结果；`containsKey` 区分「未测速」与「超时」。
  final Map<String, int?> delays;

  /// 结果为 TCP 近似值（内核未运行或回退）的节点名，文案加 `≈`。
  final Set<String> approx;

  /// 当前 DEFAULT 组的出口节点（节点行右侧显示「当前」徽章）。
  final String? currentName;

  /// 「测速全部」入口；null 时不显示。
  final VoidCallback? onTestAll;

  /// 测速进行中：禁用入口并显示 [testProgress]。
  final bool testing;
  final String? testProgress;

  @override
  State<_NodeListCard> createState() => _NodeListCardState();
}

class _NodeListCardState extends State<_NodeListCard> {
  bool _expanded = false;

  /// 同一时刻只允许一行左滑展开。
  String? _swipedNode;

  String _delayText(String name) {
    final delays = widget.delays;
    if (!delays.containsKey(name)) return '未测速';
    return formatDelay(delays[name], approx: widget.approx.contains(name));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final count = widget.nodes.length;
    return DragTarget<DragNodeData>(
      onWillAcceptWithDetails: (d) => d.data.fromGroup != null,
      onAcceptWithDetails: (d) => widget.onDrop(d.data),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return AppCard(
          color: active ? scheme.primaryContainer : null,
          borderColor: _dropBorder(scheme, active),
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.lg,
            Insets.md,
          ),
          onTap: () => setState(() => _expanded = !_expanded),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    active ? Icons.move_to_inbox : Icons.list_alt_outlined,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: Insets.sm),
                  Text('节点列表', style: display(15, weight: 600)),
                  const SizedBox(width: Insets.sm),
                  Text(
                    '$count',
                    style: mono(11.5, color: scheme.onSurfaceVariant),
                  ),
                  const Spacer(),
                  if (widget.onTestAll != null)
                    IconButton(
                      tooltip: widget.testing
                          ? (widget.testProgress ?? '测速中')
                          : '测速全部',
                      visualDensity: VisualDensity.compact,
                      onPressed: widget.testing ? null : widget.onTestAll,
                      icon: const Icon(Icons.speed, size: 20),
                    ),
                  // 添加节点放在区头，空列表时也是唯一可见入口，不用滚到底部按钮。
                  IconButton(
                    tooltip: '添加节点',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: motion.arrow,
                    curve: motion.enter,
                    child: Icon(
                      Icons.expand_more,
                      size: 20,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                widget.testProgress ??
                    (active
                        ? '松手就从当前组移除'
                        : (_expanded ? '点行编辑，长按拖到组卡' : '点这里展开；所有节点都在，不管有没有进组')),
                style: widget.testProgress == null
                    ? hintStyle(context)
                    : mono(11, color: scheme.primary),
              ),
              AnimatedSize(
                duration: motion.expand,
                curve: motion.enter,
                alignment: Alignment.topCenter,
                child: !_expanded
                    ? const SizedBox(width: double.infinity)
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const SizedBox(height: Insets.md),
                          if (count == 0)
                            Text('还没有节点：点右上角「+」添加。', style: hintStyle(context))
                          else
                            Column(
                              children: [
                                for (
                                  var i = 0;
                                  i < widget.nodes.length;
                                  i++
                                ) ...[
                                  if (i > 0) const SizedBox(height: 6),
                                  NodeRow(
                                    key: ValueKey(
                                      'node-row-${widget.nodes[i].name}',
                                    ),
                                    node: widget.nodes[i],
                                    delayText: _delayText(widget.nodes[i].name),
                                    selected:
                                        widget.currentName ==
                                        widget.nodes[i].name,
                                    open: _swipedNode == widget.nodes[i].name,
                                    onOpenChanged: (open) => setState(
                                      () => _swipedNode = open
                                          ? widget.nodes[i].name
                                          : null,
                                    ),
                                    onTap: () => widget.onOpen(widget.nodes[i]),
                                    onMenu: widget.onMenuNode == null
                                        ? null
                                        : () => widget.onMenuNode!(
                                            widget.nodes[i],
                                          ),
                                    onDelete: () =>
                                        widget.onDelete(widget.nodes[i]),
                                  ),
                                ],
                              ],
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 策略组区顶部的工具行：标题 + 「新建组」入口。
///
/// 放在节点列表之后、组卡之前，空列表时也能直接看到入口。
class _GroupsToolRow extends StatelessWidget {
  const _GroupsToolRow({required this.onCreate});

  final VoidCallback onCreate;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('策略组', style: display(14, weight: 700)),
              const SizedBox(height: 2),
              Text('把节点分组，规则按组切走', style: hintStyle(context)),
            ],
          ),
        ),
        OutlinedButton.icon(
          onPressed: onCreate,
          icon: const Icon(Icons.create_new_folder_outlined, size: 18),
          label: const Text('新建组'),
          style: OutlinedButton.styleFrom(visualDensity: VisualDensity.compact),
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({
    required this.group,
    required this.swipeOpen,
    required this.onSwipeOpenChanged,
    required this.state,
    required this.onOpenNode,
    required this.onMove,
    required this.onDeleteNode,
    required this.onEdit,
    required this.onDelete,
    required this.onAddMember,
    required this.onDrop,
    required this.onRemove,
    this.onDropRule,
    this.onMenuNode,
    this.selectedName,
    this.onSelectMember,
    this.isAuto = false,
    this.onTestGroup,
    this.testing = false,
    this.delays = const <String, int?>{},
    this.approx = const <String>{},
    this.onRelayInsert,
    this.onRelayReorder,
  });

  final GroupEntry group;

  /// 标题行是否左滑展开（只有标题行跟著滑，成员与规则区固定）。
  final bool swipeOpen;
  final ValueChanged<bool> onSwipeOpenChanged;

  final EditorState state;
  final void Function(ProxyEntry) onOpenNode;
  final void Function(ProxyEntry, String?) onMove;
  final void Function(ProxyEntry) onDeleteNode;

  /// 手机上点芯片右侧 ⋮ 打开操作表（编辑 / 移动 / 从组移除 / 删除）。
  final void Function(ProxyEntry, String?)? onMenuNode;

  /// 运行期这个组当前选中的节点名（用于高亮）。
  final String? selectedName;

  /// 非空时，点成员胶囊 = 让这个组改用该成员。
  ///
  /// 节点、策略组、系统策略（DIRECT / REJECT）走同一个回调：
  /// 以前只给 NodeChip 接线，DIRECT/REJECT 胶囊的 onTap 一直是 null。
  final void Function(String name)? onSelectMember;

  /// true = 「自动选择」卡：成员随节点同步、只读、按测速选出口。
  final bool isAuto;

  /// 「测本组」入口；null 时不显示。
  final VoidCallback? onTestGroup;

  /// 手动测速进行中（禁用入口）。
  final bool testing;

  /// 成员芯片上的延迟胶囊数据；`containsKey` 区分「未测速」与「超时」。
  final Map<String, int?> delays;

  /// 结果为 TCP 近似值（内核未运行或回退）的节点名，文案加 `≈`。
  final Set<String> approx;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddMember;
  final void Function(DragMemberData) onDrop;
  final void Function(String) onRemove;

  /// 从「本组规则」拖过来的规则：直接把 target 改成这个组。
  final void Function(RuleEntry)? onDropRule;

  /// 链式代理：把节点插到某一阶（index 在 0..N 之间）。
  final void Function(String node, int index)? onRelayInsert;

  /// 链式代理：链内调整顺序。
  final void Function(int from, int to)? onRelayReorder;

  /// 当前实际出口：自动组按最低延迟推断，fallback 用运行时选中值。
  String? get _currentLabel {
    if (group.type == 'load-balance') {
      return group.members.isEmpty ? null : '自动均衡 · ${group.members.length} 节点';
    }
    if (group.type != 'url-test' && group.type != 'fallback') {
      return selectedName != null && group.members.contains(selectedName)
          ? '当前 $selectedName'
          : null;
    }
    String? best;
    int? bestDelay;
    for (final name in group.members) {
      final delay = delays[name];
      if (delay == null) continue;
      if (bestDelay == null || delay < bestDelay) {
        best = name;
        bestDelay = delay;
      }
    }
    best ??= selectedName != null && group.members.contains(selectedName)
        ? selectedName
        : null;
    if (best == null) return null;
    return group.type == 'url-test' ? '当前 $best · 最低延迟' : '当前 $best';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = state.profile;
    final currentLabel = _currentLabel;
    final issue = groupCardIssue(group: group, profile: profile);
    final issueColor = issue == GroupCardIssue.error
        ? scheme.error
        : issue == GroupCardIssue.warning
        ? context.semantic.warn
        : null;
    // 链式卡只接受链内插入，整卡不再是投放目标。
    final isRelay = group.type == 'relay';
    final acceptsNested = acceptsGroupMembers(group);

    bool acceptsGroup(DragGroupData data, Profile profile) =>
        shouldAcceptGroupDrop(
          groups: profile.groupByName,
          name: data.name,
          fromGroup: data.fromGroup,
          targetGroup: group.name,
        );

    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) {
        final data = d.data;
        if (data is DragMemberData) {
          final alreadyMember = group.members.contains(data.name);
          final accept = data is DragGroupData
              ? acceptsGroup(data, profile)
              : shouldAcceptNodeDrop(
                  fromGroup: data.fromGroup,
                  targetGroup: group.name,
                  relay: isRelay,
                  alreadyMember: alreadyMember,
                );
          final duplicate =
              !accept &&
              (data is DragNodeData || acceptsNested) &&
              shouldHintDuplicate(
                fromGroup: data.fromGroup,
                targetGroup: group.name,
                alreadyMember: alreadyMember,
              );
          dragState.hintDuplicate(duplicate ? group.name : null);
          return accept;
        }
        if (data is RuleDragData) {
          dragState.clearHint();
          return data.rule.target != group.name;
        }
        return false;
      },
      onMove: (d) {
        final data = d.data;
        if (data is DragMemberData) {
          if (data is DragGroupData && !acceptsNested) {
            dragState.clearHint();
            return;
          }
          if (isRelay) {
            // 链式组只接受链内重排：同组拖整卡标 🚫，松手走回弹。
            dragState.hintDuplicate(
              data.fromGroup == group.name ? group.name : null,
            );
            return;
          }
          final duplicate =
              data.fromGroup != group.name && group.members.contains(data.name);
          dragState.hintDuplicate(duplicate ? group.name : null);
        }
      },
      onLeave: (_) {
        if (dragState.duplicateGroup == group.name) dragState.clearHint();
      },
      onAcceptWithDetails: (d) {
        final data = d.data;
        if (data is DragMemberData) {
          if (data is DragGroupData) {
            if (!acceptsGroup(data, state.profile)) return;
          } else if (data.fromGroup == group.name ||
              group.members.contains(data.name)) {
            return;
          }
          dragState.markAccepted();
          onDrop(data);
        } else if (data is RuleDragData) {
          dragState.markAccepted();
          onDropRule?.call(data.rule);
        }
      },
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        final duplicate = dragState.duplicateGroup == group.name;
        final ruleDrop = candidate.any((data) => data is RuleDragData);
        return AppCard(
          color:
              issueColor?.withValues(alpha: 0.06) ??
              (ruleDrop ? scheme.primaryContainer : null),
          // 红/黄问题优先于「当前出口」的紫色提示；链式卡不做整卡高亮。
          borderColor: duplicate && !isRelay
              ? scheme.error
              : issueColor ??
                    (currentLabel != null && !active
                        ? scheme.primary.withValues(alpha: 0.35)
                        : _dropBorder(scheme, active)),
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.sm,
            Insets.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MotionSize(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SlidableRow(
                      open: swipeOpen,
                      onOpenChanged: onSwipeOpenChanged,
                      actionLabel: '删除',
                      // 标题行在 AppCard 内：红块按卡片圆角裁，不越过行矩形。
                      borderRadius: BorderRadius.all(Radiuses.card),
                      onAction: onDelete,
                      child: Row(
                        children: [
                          Container(
                            width: 32,
                            height: 32,
                            decoration: BoxDecoration(
                              color: scheme.primary.withValues(alpha: 0.10),
                              borderRadius: BorderRadius.circular(Radiuses.xs),
                              border: Border.all(
                                color: scheme.primary.withValues(alpha: 0.20),
                              ),
                            ),
                            child: Icon(
                              groupIcon(group.type),
                              size: 20,
                              color: scheme.primary,
                            ),
                          ),
                          const SizedBox(width: Insets.md),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  group.name,
                                  style: display(
                                    16,
                                    weight: 700,
                                    letterSpacing: -0.2,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                if (group.type == 'relay')
                                  Text(
                                    '整链 · ${group.members.length} 阶',
                                    style: mono(
                                      10.5,
                                      color: scheme.onSurfaceVariant,
                                      letterSpacing: 0.4,
                                    ),
                                  )
                                else
                                  Row(
                                    children: [
                                      if (isAuto)
                                        Pill(
                                          label: '自动测速',
                                          color: scheme.tertiary,
                                          dense: true,
                                        )
                                      else
                                        Text(
                                          group.typeLabel,
                                          style: mono(
                                            10.5,
                                            color: scheme.onSurfaceVariant,
                                            letterSpacing: 0.4,
                                          ),
                                        ),
                                      Text(
                                        ' · ${group.members.length} 成员',
                                        style: mono(
                                          10.5,
                                          color: scheme.onSurfaceVariant,
                                        ),
                                      ),
                                      if (group.computedMembers) ...[
                                        const SizedBox(width: Insets.xs),
                                        Pill(
                                          label: '运行时决定',
                                          color: scheme.tertiary,
                                          dense: true,
                                        ),
                                      ],
                                    ],
                                  ),
                                // 链式代理没有「当前节点」：选中的是整条链。
                                if (currentLabel != null &&
                                    group.type != 'relay') ...[
                                  const SizedBox(height: 4),
                                  // 单独一行，避免和类型/成员数挤在同一行被省略号截断。
                                  Text(
                                    currentLabel,
                                    style: mono(
                                      10.5,
                                      color: scheme.primary,
                                      weight: 600,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ],
                            ),
                          ),
                          if (onTestGroup != null && group.members.isNotEmpty)
                            IconButton(
                              tooltip: testing ? '测速中…' : '测本组',
                              visualDensity: VisualDensity.compact,
                              onPressed: testing ? null : onTestGroup,
                              icon: const Icon(Icons.speed, size: 20),
                            ),
                          if (!isAuto)
                            IconButton(
                              tooltip: group.computedMembers
                                  ? '成员由 filter 决定'
                                  : '添加成员',
                              onPressed: group.computedMembers
                                  ? null
                                  : onAddMember,
                              icon: const Icon(
                                Icons.add_circle_outline,
                                size: 20,
                              ),
                            ),
                          if (!isAuto)
                            IconButton(
                              tooltip: '组设置',
                              onPressed: onEdit,
                              icon: const Icon(Icons.more_vert, size: 20),
                            ),
                        ],
                      ),
                    ),
                    if (group.members.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: Insets.md),
                        child: Text(
                          isAuto
                              ? '还没有节点：添加节点后由内核按测速结果自动选择。'
                              : group.computedMembers
                              ? '成员由 filter / include-all 在运行时决定，不在这里维护。'
                              : '还没有成员：点右上 ⊕ 添加，或把节点拖进来。',
                          style: hintStyle(context),
                        ),
                      )
                    else ...[
                      const SizedBox(height: Insets.md),
                      const Hairline(),
                      Padding(
                        padding: const EdgeInsets.only(
                          top: Insets.md,
                          right: Insets.sm,
                        ),
                        child: group.type == 'relay'
                            ? RelayChain(
                                group: group,
                                profile: profile,
                                delays: delays,
                                approx: approx,
                                onOpen: onOpenNode,
                                onDelete: onDeleteNode,
                                onRemove: onRemove,
                                onInsertAt: (node, index) =>
                                    onRelayInsert?.call(node, index),
                                onMoveLeft: (from, to) =>
                                    onRelayReorder?.call(from, to),
                                // 菜单给的是相邻索引，moveGroupMember 的 to 是插入
                                // gap 索引：右移要落到下一阶之后，才能真的后移一位。
                                onMoveRight: (from, to) =>
                                    onRelayReorder?.call(from, to + 1),
                                onMoveMember: (from, to) =>
                                    onRelayReorder?.call(from, to),
                                onAddMember: onAddMember,
                                onSelect: onSelectMember,
                                onMenu: onMenuNode == null
                                    ? null
                                    : (node, index) =>
                                          onMenuNode!(node, group.name),
                              )
                            : Wrap(
                                spacing: Insets.sm,
                                runSpacing: Insets.sm,
                                children: [
                                  for (final name in group.members) ...[
                                    if (profile.proxyByName[name]
                                        case final node?)
                                      MotionEntrance(
                                        key: ValueKey('member-$name'),
                                        child: NodeChip(
                                          node: node,
                                          fromGroup: group.name,
                                          onOpen: () => onOpenNode(node),
                                          onMove: () =>
                                              onMove(node, group.name),
                                          onDelete: () => onDeleteNode(node),
                                          onRemove: isAuto
                                              ? null
                                              : () => onRemove(name),
                                          selected: selectedName == node.name,
                                          delayText: delays.containsKey(name)
                                              ? formatDelay(
                                                  delays[name],
                                                  approx: approx.contains(name),
                                                )
                                              : null,
                                          onSelect: onSelectMember == null
                                              ? null
                                              : () =>
                                                    onSelectMember!(node.name),
                                          onMenu: isAuto || onMenuNode == null
                                              ? null
                                              : () => onMenuNode!(
                                                  node,
                                                  group.name,
                                                ),
                                        ),
                                      )
                                    else if (profile.groupByName[name]
                                        case final nested?)
                                      MotionEntrance(
                                        key: ValueKey('member-$name'),
                                        child: GroupChip(
                                          name: name,
                                          members: nested.members.length,
                                          type: nested.type,
                                          selected: selectedName == name,
                                          fromGroup:
                                              isAuto || group.computedMembers
                                              ? null
                                              : group.name,
                                          tooltip:
                                              '策略组「$name」：组里套组，内核按它的类型再选一次',
                                          onTap: onSelectMember == null
                                              ? null
                                              : () => onSelectMember!(name),
                                          onRemove: () => onRemove(name),
                                        ),
                                      )
                                    else if (Profile.builtinTargets.contains(
                                      name,
                                    ))
                                      MotionEntrance(
                                        key: ValueKey('member-$name'),
                                        child: SystemPolicyChip(
                                          name: name,
                                          note: name == 'REJECT-DROP'
                                              ? '不常用'
                                              : null,
                                          selected: selectedName == name,
                                          tooltip:
                                              '内置出站「$name」：由内核直接处理，不是配置里的节点',
                                          onTap: onSelectMember == null
                                              ? null
                                              : () => onSelectMember!(name),
                                          onRemove: () => onRemove(name),
                                        ),
                                      )
                                    else
                                      MotionEntrance(
                                        key: ValueKey('member-$name'),
                                        child: InputChip(
                                          label: Text(name),
                                          avatar: Icon(
                                            Icons.help_outline,
                                            size: 16,
                                            color: scheme.error,
                                          ),
                                          onDeleted: () => onRemove(name),
                                          deleteButtonTooltipMessage:
                                              '从组里移除（这个成员在内核里不存在）',
                                        ),
                                      ),
                                  ],
                                ],
                              ),
                      ),
                    ],
                  ],
                ),
              ),
              GroupRulesBlock(state: state, target: group.name),
            ],
          ),
        );
      },
    );
  }
}

/// 系统策略（DIRECT / REJECT）只读卡。
///
/// 不能改名、不能删组、不能加节点，但可以挂规则：卡内就是共用规则区块。
class _SystemPolicyCard extends StatelessWidget {
  const _SystemPolicyCard({
    required this.state,
    required this.target,
    required this.subtitle,
    this.onDropRule,
  });

  final EditorState state;
  final String target;
  final String subtitle;

  /// 从「本组规则」拖过来的规则：把 target 改成这个系统策略。
  final void Function(RuleEntry)? onDropRule;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    // 系统策略组本身只读，但允许把规则拖进来改挂到 DIRECT / REJECT。
    return DragTarget<Object>(
      onWillAcceptWithDetails: (d) {
        final data = d.data;
        return data is RuleDragData && data.rule.target != target;
      },
      onAcceptWithDetails: (d) {
        final data = d.data;
        if (data is RuleDragData) onDropRule?.call(data.rule);
      },
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return AppCard(
          borderColor: _dropBorder(scheme, active),
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.lg,
            Insets.lg,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    decoration: BoxDecoration(
                      color: scheme.tertiary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(Radiuses.xs),
                      border: Border.all(
                        color: scheme.tertiary.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Icon(
                      builtinIcon(target),
                      size: 20,
                      color: scheme.tertiary,
                    ),
                  ),
                  const SizedBox(width: Insets.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          target,
                          style: display(16, weight: 700, letterSpacing: -0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(subtitle, style: hintStyle(context)),
                      ],
                    ),
                  ),
                  Pill(label: '系统策略', color: scheme.tertiary, dense: true),
                ],
              ),
              GroupRulesBlock(
                state: state,
                target: target,
                newRuleLabel: '添加规则',
              ),
            ],
          ),
        );
      },
    );
  }
}

/// 新建策略组的结果。
class _NewGroupSpec {
  const _NewGroupSpec({
    required this.name,
    required this.type,
    this.withDirect = true,
    this.withReject = false,
  });

  final String name;
  final String type;

  /// 新组初始成员：DIRECT 默认勾上，REJECT 默认不勾。
  final bool withDirect;
  final bool withReject;
}

/// 新建策略组对话框。
///
/// 控制器归这个 State 所有：早先的写法是在调用方 `await showDialog(...)` 之后立刻
/// `dispose()`，而对话框还在退场动画里引用控制器，会撞 `_dependents.isEmpty` 断言。
class _NewGroupDialog extends StatefulWidget {
  const _NewGroupDialog();

  @override
  State<_NewGroupDialog> createState() => _NewGroupDialogState();
}

class _NewGroupDialogState extends State<_NewGroupDialog> {
  final TextEditingController _ctrl = TextEditingController();
  String _type = 'select';
  bool _withDirect = true;
  bool _withReject = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return EditDialog(
      title: '新建策略组',
      confirmLabel: '创建',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(controller: _ctrl, autofocus: true, label: '组名'),
          const SizedBox(height: 12),
          AppDropdown<String>(
            label: '类型',
            expand: true,
            value: _type,
            options: [
              for (final t in kGroupTypes)
                DropdownOption(t, _ProxyBoardState._groupTypeLabel(t)),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          const SizedBox(height: 4),
          SelectableTile(
            selected: _withDirect,
            onTap: () => setState(() => _withDirect = !_withDirect),
            leading: Icon(
              Icons.arrow_outward,
              size: 16,
              color: scheme.tertiary,
            ),
            title: const Text('添加 DIRECT'),
            subtitle: Text('直连：不经过代理，作为兜底出口', style: hintStyle(context)),
          ),
          SelectableTile(
            selected: _withReject,
            onTap: () => setState(() => _withReject = !_withReject),
            leading: Icon(Icons.block, size: 16, color: scheme.error),
            title: const Text('添加 REJECT'),
            subtitle: Text('拒绝：命中即断开，不发请求', style: hintStyle(context)),
          ),
        ],
      ),
      onConfirm: () => Navigator.pop(
        context,
        _NewGroupSpec(
          name: _ctrl.text.trim(),
          type: _type,
          withDirect: _withDirect,
          withReject: _withReject,
        ),
      ),
      onCancel: () => Navigator.pop(context),
    );
  }
}

/// 编辑策略组的结果。
class _GroupEditResult {
  const _GroupEditResult({
    required this.name,
    required this.type,
    required this.url,
    required this.interval,
    required this.hidden,
  });

  final String name;
  final String type;
  final String url;
  final String interval;
  final bool hidden;
}

/// 编辑策略组对话框（控制器同样归 State 所有，理由见 [_NewGroupDialog]）。
class _EditGroupDialog extends StatefulWidget {
  const _EditGroupDialog({required this.group});

  final GroupEntry group;

  @override
  State<_EditGroupDialog> createState() => _EditGroupDialogState();
}

class _EditGroupDialogState extends State<_EditGroupDialog> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _urlCtrl;
  late final TextEditingController _intervalCtrl;
  late String _type;

  @override
  void initState() {
    super.initState();
    final group = widget.group;
    _nameCtrl = TextEditingController(text: group.name);
    _urlCtrl = TextEditingController(text: '${group.raw['url'] ?? ''}');
    _intervalCtrl = TextEditingController(
      text: '${group.raw['interval'] ?? ''}',
    );
    _type = group.type;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _urlCtrl.dispose();
    _intervalCtrl.dispose();
    super.dispose();
  }

  bool get _timed =>
      _type == 'url-test' || _type == 'fallback' || _type == 'load-balance';

  @override
  Widget build(BuildContext context) {
    return EditDialog(
      title: '编辑策略组',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppTextField(
            controller: _nameCtrl,
            label: '组名',
            helper: '改名会同步规则与其它组里的引用',
          ),
          const SizedBox(height: 12),
          AppDropdown<String>(
            label: '类型',
            expand: true,
            value: _type,
            options: [
              for (final t in kGroupTypes)
                DropdownOption(t, _ProxyBoardState._groupTypeLabel(t)),
            ],
            onChanged: (v) => setState(() => _type = v),
          ),
          if (_timed) ...[
            const SizedBox(height: 12),
            AppTextField(controller: _urlCtrl, label: '测速 URL'),
            const SizedBox(height: 12),
            AppTextField(
              controller: _intervalCtrl,
              keyboardType: TextInputType.number,
              label: '间隔（秒）',
            ),
          ],
        ],
      ),
      onConfirm: () => Navigator.pop(
        context,
        _GroupEditResult(
          name: _nameCtrl.text.trim(),
          type: _type,
          url: _urlCtrl.text,
          interval: _intervalCtrl.text,
          hidden: widget.group.raw['hidden'] == true,
        ),
      ),
      onCancel: () => Navigator.pop(context),
    );
  }
}
