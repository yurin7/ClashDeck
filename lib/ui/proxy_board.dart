import 'package:material_ui/material_ui.dart';

import '../core/edit/member_picker.dart';
import '../core/edit/config_ops.dart';
import '../core/edit/group_selection.dart';
import '../core/model/profile.dart';
import '../core/schema/group_schema.dart';
import '../core/yaml/yaml_doc.dart';
import '../runtime/runtime_controller.dart';
import '../state/editor_state.dart';
import 'import_dialogs.dart';
import 'dropdown.dart';
import 'fields.dart';
import 'rules/group_rules_block.dart';
import 'chips.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';
import 'node_form_page.dart';

/// 「添加节点」的三种入口。
enum _AddMode { manual, links, subscription }

/// 按策略组组织的节点面板：跨组拖拽、增删节点、改组成员。
class ProxyBoard extends StatefulWidget {
  const ProxyBoard({
    super.key,
    required this.state,
    this.onSubscriptionSaved,
    this.runtime,
    this.groupSelection = const <String, String>{},
    this.onGroupSelection,
  });

  final EditorState state;

  /// 用户导入/记下订阅地址时回调（编辑器用它把地址写进 sidecar meta）。
  final Future<void> Function(String url)? onSubscriptionSaved;

  /// 非空时，组内点节点 = 让这个组改用该节点（运行期切换）。
  final RuntimeController? runtime;

  /// 每个组上次选中的节点（sidecar 里记的选择）。停止状态下也用它做高亮。
  final Map<String, String> groupSelection;

  /// 点组内节点时回调：把这次选择记进当前配置的 sidecar，重开仍在。
  final Future<void> Function(String group, String node)? onGroupSelection;

  @override
  State<ProxyBoard> createState() => _ProxyBoardState();
}

class _ProxyBoardState extends State<ProxyBoard> {
  EditorState get s => widget.state;

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
      MaterialPageRoute(
        builder: (_) =>
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
    if (!s.addGroupMember(target, '${result['name']}')) _fail();
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
      MaterialPageRoute(
        builder: (_) => NodeFormPage(
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
  /// 关键点：选择先写进 sidecar（`meta.app.groupNodes`），不依赖内核在跑。
  /// 内核运行中再顺带调一次接口立刻生效；停止状态下只记偏好、刷 UI，
  /// 不弹「请先启动内核」，也不报错——下次启动内核会自动应用。
  Future<void> _selectNodeForGroup(String group, ProxyEntry node) async {
    final runtime = widget.runtime;
    final running = runtime != null && runtime.phase == RuntimePhase.running;
    await widget.onGroupSelection?.call(group, node.name);
    if (!mounted) return;
    setState(() {});
    if (!running) return;
    final ok = await runtime.selectNode(group, node.name);
    if (!ok) {
      _toast('切换失败，内核可能已经退出');
      return;
    }
    _toast('「$group」现在用 ${node.name}');
  }

  Future<void> _deleteNode(ProxyEntry node) async {
    final ok = await _confirm('删除节点「${node.name}」？', '会同时从所有策略组里移除它。');
    if (ok != true) return;
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
    return showAppDialog<String>(
      context,
      builder: (ctx) => SimpleDialog(
        title: Text(title),
        children: [
          for (final g in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.name),
              child: Text('${g.name}  ·  ${g.typeLabel}'),
            ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('跳过'),
          ),
        ],
      ),
    );
  }

  Future<void> _moveDialog(ProxyEntry node, String? fromGroup) async {
    final groups = s.profile.groups.where((g) => g.name != fromGroup).toList();
    if (groups.isEmpty) return;
    final target = await showAppDialog<String>(
      context,
      builder: (ctx) => SimpleDialog(
        title: Text('把「${node.name}」移动到…'),
        children: [
          for (final g in groups)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, g.name),
              child: Text(g.name),
            ),
        ],
      ),
    );
    if (target == null) return;
    final ok = fromGroup == null
        ? s.addGroupMember(target, node.name)
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

  Future<bool?> _confirm(String title, String message) => showAppDialog<bool>(
    context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('确定'),
        ),
      ],
    ),
  );

  Future<void> _deleteGroup(GroupEntry group) async {
    final ok = await _confirm('删除策略组「${group.name}」？', '引用它的规则会变成悬空引用，校验会提示。');
    if (ok != true) return;
    if (!s.apply((d) => ConfigOps.deleteGroup(d, group.name))) _fail();
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
    // 高亮用的选择：sidecar 里记的优先，运行中的实际选择覆盖它（会话内切换不回写）。
    final selection = <String, String>{
      ...groupSelectionSnapshot(profile, widget.groupSelection),
      ...?widget.runtime?.selected,
    };
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

    return ListView(
      padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 120),
      children: [
        SectionTitle(
          title: 'PROXIES',
          subtitle: '点节点编辑，长按拖到别的组；× 从本组移除',
          icon: Icons.hub_outlined,
          trailing: Text(
            '${profile.proxies.length} 节点 · ${profile.groups.length} 组',
            style: mono(11, color: scheme.onSurfaceVariant, letterSpacing: 0.3),
          ),
        ),
        _NodeListCard(
          nodes: profile.proxies,
          onOpen: _editNode,
          onMove: (n) => _moveDialog(n, null),
          onDelete: _deleteNode,
          onMenuNode: (n) => _showNodeActions(n),
          onAdd: _addNode,
          onDrop: (data) {
            if (data.fromGroup == null) return;
            final ok = s.removeGroupMember(data.fromGroup!, data.node);
            if (!ok) _fail();
          },
        ),
        const SizedBox(height: Insets.md),
        _GroupsToolRow(onCreate: _addGroup),
        for (final group in groups)
          Padding(
            padding: const EdgeInsets.only(top: Insets.md),
            child: _GroupCard(
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
              onSelectNode: group.name == kAutoGroupName
                  ? (_) => _toast('「自动选择」按测速结果自动选，不能手动切')
                  : widget.runtime == null && widget.onGroupSelection == null
                  ? null
                  : (n) => _selectNodeForGroup(group.name, n),
              onEdit: () => _editGroup(group),
              onDelete: () => _deleteGroup(group),
              onAddMember: () async {
                final picked = await _pickMembers(profile, group);
                if (picked == null || picked.isEmpty) return;
                var added = 0;
                for (final name in picked) {
                  if (s.addGroupMember(group.name, name)) added++;
                }
                if (added == 0) {
                  _fail();
                  return;
                }
                // 组头计数直接读 state，刷新一次就能看到新成员。
                if (mounted) {
                  setState(() {});
                  _toast('已加入 \$added 个');
                }
              },
              onDrop: (data) {
                final ok = data.fromGroup == null
                    ? s.addGroupMember(group.name, data.node)
                    : s.moveMember(data.node, data.fromGroup!, group.name);
                if (!ok) _fail();
              },
              onRemove: (name) {
                if (!s.removeGroupMember(group.name, name)) _fail();
              },
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
          _SystemPolicyCard(state: s, target: name, subtitle: subtitle),
        ],
        const SizedBox(height: Insets.xl),
      ],
    );
  }

  /// 「选择要加入的节点」底部弹窗。
  ///
  /// 返回要加进这个组的成员；返回 `null` 表示放弃。三种情况都要能走下去：
  /// 有候选就多选、全局没节点就引导去新建、全在组里也要给新建入口。
  Future<List<String>?> _pickMembers(Profile profile, GroupEntry group) {
    return showAppSheet<List<String>>(
      context,
      title: '选择要加入的节点',
      subtitle: '向「${group.name}」批量添加成员',
      body: (ctx) => _AddMemberSheet(
        profile: profile,
        groupName: group.name,
        members: group.members,
        onCreateNode: () {
          Navigator.pop(ctx);
          _addNodeForm();
        },
      ),
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
    required this.onMove,
    required this.onDelete,
    required this.onDrop,
    required this.onAdd,
    this.onMenuNode,
  });

  final List<ProxyEntry> nodes;
  final void Function(ProxyEntry) onOpen;
  final void Function(ProxyEntry) onMove;
  final void Function(ProxyEntry) onDelete;
  final void Function(DragNodeData) onDrop;

  /// 区头的「添加节点」入口，和底部「新建组」并列。
  final VoidCallback onAdd;

  /// 手机上点芯片右侧 ⋮ 打开操作表（编辑 / 移动 / 删除）。
  final void Function(ProxyEntry)? onMenuNode;

  @override
  State<_NodeListCard> createState() => _NodeListCardState();
}

class _NodeListCardState extends State<_NodeListCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
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
                    size: 17,
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
                  // 添加节点放在区头，空列表时也是唯一可见入口，不用滚到底部按钮。
                  IconButton(
                    tooltip: '添加节点',
                    visualDensity: VisualDensity.compact,
                    onPressed: widget.onAdd,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                ],
              ),
              const SizedBox(height: 3),
              Text(
                active
                    ? '松手就从当前组移除'
                    : (_expanded ? '点节点编辑，长按拖到组里' : '点这里展开；所有节点都在，不管有没有进组'),
                style: hintStyle(context),
              ),
              if (_expanded) ...[
                const SizedBox(height: Insets.md),
                if (count == 0)
                  Text('还没有节点：点右上角「+」添加。', style: hintStyle(context))
                else
                  Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: [
                      for (final n in widget.nodes)
                        NodeChip(
                          node: n,
                          fromGroup: null,
                          onOpen: () => widget.onOpen(n),
                          onMove: () => widget.onMove(n),
                          onDelete: () => widget.onDelete(n),
                          onRemove: null,
                          onMenu: widget.onMenuNode == null
                              ? null
                              : () => widget.onMenuNode!(n),
                        ),
                    ],
                  ),
              ],
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
    required this.state,
    required this.onOpenNode,
    required this.onMove,
    required this.onDeleteNode,
    required this.onEdit,
    required this.onDelete,
    required this.onAddMember,
    required this.onDrop,
    required this.onRemove,
    this.onMenuNode,
    this.selectedName,
    this.onSelectNode,
    this.isAuto = false,
  });

  final GroupEntry group;
  final EditorState state;
  final void Function(ProxyEntry) onOpenNode;
  final void Function(ProxyEntry, String?) onMove;
  final void Function(ProxyEntry) onDeleteNode;

  /// 手机上点芯片右侧 ⋮ 打开操作表（编辑 / 移动 / 从组移除 / 删除）。
  final void Function(ProxyEntry, String?)? onMenuNode;

  /// 运行期这个组当前选中的节点名（用于高亮）。
  final String? selectedName;

  /// 非空时，点芯片 = 让这个组改用该节点。
  final void Function(ProxyEntry)? onSelectNode;

  /// true = 「自动选择」卡：成员随节点同步、只读、按测速选出口。
  final bool isAuto;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddMember;
  final void Function(DragNodeData) onDrop;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = state.profile;
    return DragTarget<DragNodeData>(
      onWillAcceptWithDetails: (d) => d.data.fromGroup != group.name,
      onAcceptWithDetails: (d) => onDrop(d.data),
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return AppCard(
          color: active ? scheme.primaryContainer : null,
          borderColor: _dropBorder(scheme, active),
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.sm,
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
                      color: scheme.primary.withValues(alpha: 0.10),
                      borderRadius: BorderRadius.circular(Radiuses.xs),
                      border: Border.all(
                        color: scheme.primary.withValues(alpha: 0.20),
                      ),
                    ),
                    child: Icon(
                      groupIcon(group.type),
                      size: 17,
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
                          style: display(16, weight: 700, letterSpacing: -0.2),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
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
                              style: mono(10.5, color: scheme.onSurfaceVariant),
                            ),
                            if (selectedName != null &&
                                group.members.contains(selectedName))
                              Flexible(
                                child: Text(
                                  ' · 当前 $selectedName',
                                  style: mono(
                                    10.5,
                                    color: scheme.primary,
                                    weight: 600,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
                      ],
                    ),
                  ),
                  if (!isAuto)
                    IconButton(
                      tooltip: group.computedMembers ? '成员由 filter 决定' : '添加成员',
                      onPressed: group.computedMembers ? null : onAddMember,
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                    ),
                  if (!isAuto)
                    PopupMenuButton<String>(
                      tooltip: '组设置',
                      onSelected: (v) {
                        switch (v) {
                          case 'edit':
                            onEdit();
                          case 'delete':
                            onDelete();
                        }
                      },
                      itemBuilder: (_) => const [
                        PopupMenuItem(value: 'edit', child: Text('编辑组')),
                        PopupMenuItem(value: 'delete', child: Text('删除组')),
                      ],
                    ),
                ],
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
                  child: Wrap(
                    spacing: Insets.sm,
                    runSpacing: Insets.sm,
                    children: [
                      for (final name in group.members) ...[
                        if (profile.proxyByName[name] case final node?)
                          NodeChip(
                            node: node,
                            fromGroup: group.name,
                            onOpen: () => onOpenNode(node),
                            onMove: () => onMove(node, group.name),
                            onDelete: () => onDeleteNode(node),
                            onRemove: isAuto ? null : () => onRemove(name),
                            selected: selectedName == node.name,
                            onSelect: onSelectNode == null
                                ? null
                                : () => onSelectNode!(node),
                            onMenu: isAuto || onMenuNode == null
                                ? null
                                : () => onMenuNode!(node, group.name),
                          )
                        else if (profile.groupByName[name] case final nested?)
                          GroupChip(
                            name: name,
                            members: nested.members.length,
                            type: nested.type,
                            tooltip: '策略组「$name」：组里套组，内核按它的类型再选一次',
                            onRemove: () => onRemove(name),
                          )
                        else if (Profile.builtinTargets.contains(name))
                          SystemPolicyChip(
                            name: name,
                            note: name == 'REJECT-DROP' ? '不常用' : null,
                            tooltip: '内置出站「$name」：由内核直接处理，不是配置里的节点',
                            onRemove: () => onRemove(name),
                          )
                        else
                          InputChip(
                            label: Text(name),
                            avatar: Icon(
                              Icons.help_outline,
                              size: 15,
                              color: scheme.error,
                            ),
                            onDeleted: () => onRemove(name),
                            deleteButtonTooltipMessage: '从组里移除（这个成员在内核里不存在）',
                          ),
                      ],
                    ],
                  ),
                ),
              ],
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
  });

  final EditorState state;
  final String target;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
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
                  size: 17,
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
                    const SizedBox(height: 3),
                    Text(subtitle, style: hintStyle(context)),
                  ],
                ),
              ),
              Pill(label: '系统策略', color: scheme.tertiary, dense: true),
            ],
          ),
          GroupRulesBlock(state: state, target: target, newRuleLabel: '添加规则'),
        ],
      ),
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
    return AlertDialog(
      title: const Text('新建策略组'),
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
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _withDirect,
            onChanged: (v) => setState(() => _withDirect = v ?? false),
            title: const Text('添加 DIRECT'),
            subtitle: Text('直连：不经过代理，作为兜底出口', style: hintStyle(context)),
          ),
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            controlAffinity: ListTileControlAffinity.leading,
            value: _withReject,
            onChanged: (v) => setState(() => _withReject = v ?? false),
            title: const Text('添加 REJECT'),
            subtitle: Text('拒绝：命中即断开，不发请求', style: hintStyle(context)),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _NewGroupSpec(
              name: _ctrl.text.trim(),
              type: _type,
              withDirect: _withDirect,
              withReject: _withReject,
            ),
          ),
          child: const Text('创建'),
        ),
      ],
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
  late bool _hidden;

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
    _hidden = group.raw['hidden'] == true;
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
    return AlertDialog(
      title: const Text('编辑策略组'),
      content: SingleChildScrollView(
        child: Column(
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('在面板中隐藏'),
              value: _hidden,
              onChanged: (v) => setState(() => _hidden = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            _GroupEditResult(
              name: _nameCtrl.text.trim(),
              type: _type,
              url: _urlCtrl.text,
              interval: _intervalCtrl.text,
              hidden: _hidden,
            ),
          ),
          child: const Text('保存'),
        ),
      ],
    );
  }
}

/// 组头「+」打开的底部弹窗：多选把节点/策略组加进这个组。
///
/// 三个状态都要能走：
/// - 有候选：多选后点「加入」；
/// - 整个配置没有任何节点：空态 + 直达「新建节点」；
/// - 该组已经包含所有候选：提示「全部节点已在组内」，但保留「新建节点」入口。
class _AddMemberSheet extends StatefulWidget {
  const _AddMemberSheet({
    required this.profile,
    required this.groupName,
    required this.members,
    required this.onCreateNode,
  });

  final Profile profile;
  final String groupName;
  final List<String> members;
  final VoidCallback onCreateNode;

  @override
  State<_AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<_AddMemberSheet> {
  final Set<String> _picked = <String>{};
  final TextEditingController _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  /// 全部候选（含已在组内的，置灰显示）；DIRECT / REJECT 作为系统策略可选。
  List<MemberCandidate> get _all => memberCandidates(
    widget.profile,
    groupName: widget.groupName,
    members: widget.members,
  );

  List<MemberCandidate> get _visible => filterMemberCandidates(_all, _query);

  void _selectAll() {
    setState(() {
      final next = selectVisible(_all, _query, _picked);
      _picked
        ..clear()
        ..addAll(next);
    });
  }

  void _invert() {
    setState(() {
      final next = invertVisible(_all, _query, _picked);
      _picked
        ..clear()
        ..addAll(next);
    });
  }

  void _clear() {
    setState(_picked.clear);
  }

  void _toggle(String name, bool selected) {
    setState(() {
      if (selected) {
        _picked.add(name);
      } else {
        _picked.remove(name);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final all = _all;
    final visible = _visible;
    final noNodes = widget.profile.proxies.isEmpty;
    final everythingInside = !noNodes && all.every((c) => c.inGroup);
    final selectable = all.where((c) => !c.inGroup).length;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (everythingInside) ...[
          const SizedBox(height: Insets.sm),
          Pill(
            label: '全部节点已在组内',
            icon: Icons.check_circle_outline,
            color: scheme.primary,
          ),
        ],
        const SizedBox(height: Insets.sm),
        AppTextField(
          controller: _searchCtrl,
          hint: '搜索节点或策略组',
          prefixIcon: const Icon(Icons.search, size: 18),
          suffixIcon: _query.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空搜索',
                  icon: const Icon(Icons.close, size: 16),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _query = '');
                  },
                ),
          onChanged: (value) => setState(() => _query = value),
        ),
        const SizedBox(height: Insets.xs),
        Row(
          children: [
            TextButton(
              onPressed: selectable == 0 ? null : _selectAll,
              child: const Text('全选'),
            ),
            TextButton(
              onPressed: selectable == 0 ? null : _invert,
              child: const Text('反选'),
            ),
            TextButton(
              onPressed: _picked.isEmpty ? null : _clear,
              child: const Text('清空'),
            ),
            const Spacer(),
            Pill(
              label: '已选 ${_picked.length}',
              dense: true,
              color: _picked.isEmpty ? null : scheme.primary,
            ),
          ],
        ),
        const SizedBox(height: Insets.xs),
        Flexible(
          child: noNodes
              ? _emptyState(context)
              : visible.isEmpty
              ? _noMatchState(context)
              : ListView(
                  shrinkWrap: true,
                  children: [
                    for (final candidate in visible)
                      if (!candidate.isGroup && !candidate.isBuiltin)
                        _row(context, scheme, candidate),
                    if (visible.any((c) => c.isBuiltin))
                      Padding(
                        padding: const EdgeInsets.only(
                          top: Insets.sm,
                          bottom: 2,
                        ),
                        child: MicroLabel('内置', color: scheme.onSurfaceVariant),
                      ),
                    for (final candidate in visible)
                      if (candidate.isBuiltin) _row(context, scheme, candidate),
                    if (visible.any((c) => c.isGroup))
                      Padding(
                        padding: const EdgeInsets.only(
                          top: Insets.sm,
                          bottom: 2,
                        ),
                        child: MicroLabel(
                          '策略组',
                          color: scheme.onSurfaceVariant,
                        ),
                      ),
                    for (final candidate in visible)
                      if (candidate.isGroup) _row(context, scheme, candidate),
                  ],
                ),
        ),
        const SizedBox(height: Insets.sm),
        Row(
          children: [
            TextButton.icon(
              onPressed: widget.onCreateNode,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('新建节点'),
            ),
            const Spacer(),
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            const SizedBox(width: Insets.sm),
            FilledButton(
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.pop(
                      context,
                      prunePicked(all, _picked).toList(),
                    ),
              child: Text('加入 ${_picked.length} 个'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _row(
    BuildContext context,
    ColorScheme scheme,
    MemberCandidate candidate,
  ) {
    final inside = candidate.inGroup;
    final checked = inside || _picked.contains(candidate.name);
    final note = inside
        ? '已在组内'
        : candidate.note ?? (candidate.isBuiltin ? '系统策略' : null);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Checkbox(
            value: checked,
            onChanged: inside
                ? null
                : (value) => _toggle(candidate.name, value ?? false),
          ),
          Expanded(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: inside ? null : () => _toggle(candidate.name, !checked),
              child: Align(
                alignment: Alignment.centerLeft,
                child: NameChip(
                  name: candidate.name,
                  icon: candidate.isBuiltin
                      ? builtinIcon(candidate.name)
                      : candidate.isGroup
                      ? Icons.account_tree_outlined
                      : Icons.dns_outlined,
                  selected: _picked.contains(candidate.name),
                  enabled: !inside,
                  subtitle: note,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _noMatchState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.search_off,
            size: 32,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: Insets.sm),
          Text('没有匹配「${_query.trim()}」的成员', style: display(15, weight: 600)),
          const SizedBox(height: 4),
          Text('换个关键字，或清空搜索看全部。', style: hintStyle(context)),
        ],
      ),
    );
  }

  Widget _emptyState(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.cloud_off_outlined,
            size: 32,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(height: Insets.sm),
          Text('还没有节点', style: display(15, weight: 600)),
          const SizedBox(height: 4),
          Text(
            '先建一个节点，再把它加进「${widget.groupName}」。',
            textAlign: TextAlign.center,
            style: hintStyle(context),
          ),
        ],
      ),
    );
  }
}
