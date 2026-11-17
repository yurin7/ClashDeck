import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/model/profile.dart';
import '../core/schema/group_schema.dart';
import '../core/yaml/yaml_doc.dart';
import '../runtime/runtime_controller.dart';
import '../state/editor_state.dart';
import 'import_dialogs.dart';
import 'dropdown.dart';
import 'theme.dart';
import 'widgets.dart';
import 'node_form_page.dart';

/// 「添加节点」的三种入口。
enum _AddMode { manual, links, subscription }

/// 拖拽时携带的数据。
class _DragData {
  const _DragData(this.node, this.fromGroup);
  final String node;

  /// null 表示从"未归类节点"拖出。
  final String? fromGroup;
}

/// 按策略组组织的节点面板：跨组拖拽、增删节点、改组成员。
class ProxyBoard extends StatefulWidget {
  const ProxyBoard({
    super.key,
    required this.state,
    this.onSubscriptionSaved,
    this.runtime,
  });

  final EditorState state;

  /// 用户导入/记下订阅地址时回调（编辑器用它把地址写进 sidecar meta）。
  final Future<void> Function(String url)? onSubscriptionSaved;

  /// 非空时，组内点节点 = 让这个组改用该节点（运行期切换）。
  final RuntimeController? runtime;

  @override
  State<ProxyBoard> createState() => _ProxyBoardState();
}

class _ProxyBoardState extends State<ProxyBoard> {
  EditorState get s => widget.state;

  void _fail() {
    final msg = s.lastError;
    if (msg == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------------------------------------------------------- 操作

  Future<void> _addNode() async {
    final mode = await showModalBottomSheet<_AddMode>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
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
              subtitle: const Text(
                'vless / vmess / trojan / ss / hy2 …，可以一次粘多条',
              ),
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
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
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

  /// 组内点节点 = 让这个组在运行期改用该节点。
  Future<void> _selectNodeForGroup(String group, ProxyEntry node) async {
    final runtime = widget.runtime;
    if (runtime == null) return;
    if (runtime.phase != RuntimePhase.running) {
      _toast('先启动内核，才能在配置页切换这个组的节点');
      return;
    }
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
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
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
    return showDialog<String>(
      context: context,
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
    final target = await showDialog<String>(
      context: context,
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
    final spec = await showDialog<_NewGroupSpec>(
      context: context,
      builder: (_) => const _NewGroupDialog(),
    );
    if (spec == null || spec.name.isEmpty) return;
    if (!s.apply(
      (d) => ConfigOps.addGroup(
        d,
        {'name': spec.name, 'type': spec.type},
        // 手动选择组默认带 DIRECT，刚建好就能选；测速/故障转移组不塞，免得污染测速结果。
        members: spec.type == 'select' ? const ['DIRECT'] : const [],
      ),
    )) {
      _fail();
    }
  }

  Future<void> _editGroup(GroupEntry group) async {
    final result = await showDialog<_GroupEditResult>(
      context: context,
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

  Future<bool?> _confirm(String title, String message) => showDialog<bool>(
    context: context,
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
          onDrop: (data) {
            if (data.fromGroup == null) return;
            final ok = s.removeGroupMember(data.fromGroup!, data.node);
            if (!ok) _fail();
          },
        ),
        for (final group in profile.groups)
          Padding(
            padding: const EdgeInsets.only(top: Insets.md),
            child: _GroupCard(
              group: group,
              state: s,
              onOpenNode: _editNode,
              onMove: (n, from) => _moveDialog(n, from),
              onDeleteNode: _deleteNode,
              onMenuNode: (n, from) => _showNodeActions(n, fromGroup: from),
              selectedName: widget.runtime?.selected[group.name],
              onSelectNode: widget.runtime == null
                  ? null
                  : (n) => _selectNodeForGroup(group.name, n),
              onEdit: () => _editGroup(group),
              onDelete: () => _deleteGroup(group),
              onAddMember: () async {
                final hasCandidate =
                    profile.proxies.any(
                      (p) => !group.members.contains(p.name),
                    ) ||
                    profile.groups.any(
                      (g) =>
                          g.name != group.name &&
                          !group.members.contains(g.name),
                    );
                if (!hasCandidate) {
                  _toast('「${group.name}」里已经包含所有节点和策略组，没有可添加的了');
                  return;
                }
                final picked = await _pickNode(profile, group);
                if (picked == null) return;
                if (!s.addGroupMember(group.name, picked)) _fail();
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
        const SizedBox(height: Insets.xl),
        Row(
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _addNode,
                icon: const Icon(Icons.add, size: 20),
                label: const Text('添加节点'),
              ),
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _addGroup,
                icon: const Icon(Icons.create_new_folder_outlined, size: 20),
                label: const Text('新建组'),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<String?> _pickNode(Profile profile, GroupEntry group) {
    final candidates = profile.proxies
        .where((p) => !group.members.contains(p.name))
        .toList();
    final groupCandidates = profile.groups.where(
      (g) => g.name != group.name && !group.members.contains(g.name),
    );
    final all = <String>[
      ...candidates.map((e) => e.name),
      ...groupCandidates.map((e) => e.name),
    ];
    if (all.isEmpty) return Future.value(null);
    return showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text('向「${group.name}」添加成员'),
        children: [
          for (final name in all)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, name),
              child: Text(name),
            ),
        ],
      ),
    );
  }
}

/// 组类型 → 图标，用来在卡片头上代替文字说明。
IconData groupIcon(String type) => switch (type) {
  'select' => Icons.radio_button_checked,
  'url-test' => Icons.speed,
  'fallback' => Icons.alt_route,
  'load-balance' => Icons.shuffle,
  'relay' => Icons.link,
  _ => Icons.account_tree_outlined,
};

/// 内置出站（DIRECT / REJECT / PASS…）用的小图标。
IconData _builtinIcon(String name) => switch (name) {
  'DIRECT' => Icons.arrow_outward,
  'REJECT' => Icons.block,
  'REJECT-DROP' => Icons.bolt,
  'PASS' => Icons.subdirectory_arrow_right,
  _ => Icons.public,
};

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
    this.onMenuNode,
  });

  final List<ProxyEntry> nodes;
  final void Function(ProxyEntry) onOpen;
  final void Function(ProxyEntry) onMove;
  final void Function(ProxyEntry) onDelete;
  final void Function(_DragData) onDrop;

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
    return DragTarget<_DragData>(
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
                  Text('还没有节点：点下面「添加节点」。', style: hintStyle(context))
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

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onAddMember;
  final void Function(_DragData) onDrop;
  final void Function(String) onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = state.profile;
    return DragTarget<_DragData>(
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
                  IconButton(
                    tooltip: group.computedMembers ? '成员由 filter 决定' : '添加成员',
                    onPressed: group.computedMembers ? null : onAddMember,
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
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
                    group.computedMembers
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
                            onRemove: () => onRemove(name),
                            selected: selectedName == node.name,
                            onSelect: onSelectNode == null
                                ? null
                                : () => onSelectNode!(node),
                            onMenu: onMenuNode == null
                                ? null
                                : () => onMenuNode!(node, group.name),
                          )
                        else if (profile.groupByName.containsKey(name))
                          Tooltip(
                            message: '策略组「$name」：组里套组，内核按它的类型再选一次',
                            child: InputChip(
                              avatar: Icon(
                                Icons.account_tree_outlined,
                                size: 15,
                                color: scheme.primary,
                              ),
                              label: Text(name),
                              onDeleted: () => onRemove(name),
                              deleteButtonTooltipMessage: '从组里移除',
                            ),
                          )
                        else if (Profile.builtinTargets.contains(name))
                          Tooltip(
                            message: '内置出站「$name」：由内核直接处理，不是配置里的节点',
                            child: InputChip(
                              avatar: Icon(
                                _builtinIcon(name),
                                size: 15,
                                color: scheme.tertiary,
                              ),
                              label: Text(name),
                              labelStyle: mono(12, color: scheme.tertiary),
                              onDeleted: () => onRemove(name),
                              deleteButtonTooltipMessage: '从组里移除',
                            ),
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
            ],
          ),
        );
      },
    );
  }
}

/// 一个可长按拖拽的节点芯片。
class NodeChip extends StatelessWidget {
  const NodeChip({
    super.key,
    required this.node,
    required this.fromGroup,
    required this.onOpen,
    required this.onMove,
    required this.onDelete,
    required this.onRemove,
    this.onMenu,
    this.onSelect,
    this.selected = false,
  });

  final ProxyEntry node;
  final String? fromGroup;
  final VoidCallback onOpen;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  /// 非空表示"从当前组移除"；未归类节点为 null。
  final VoidCallback? onRemove;

  /// 手机上没有右键，点这个 ⋮ 打开「编辑 / 移动 / 删除」操作表。
  final VoidCallback? onMenu;

  /// 组内芯片：点按 = 让这个组改用该节点（不打开编辑页）。
  final VoidCallback? onSelect;

  /// 该节点是否正是所属组当前选中的那个。
  final bool selected;

  static String _typeBadge(String type) => switch (type) {
    'vless' => 'V',
    'vmess' => 'M',
    'trojan' => 'T',
    'ss' => 'S',
    'ssr' => 'R',
    'hysteria2' || 'hy2' => 'H2',
    'tuic' => 'U',
    'wireguard' => 'WG',
    'socks5' => '5',
    'http' => 'H',
    'snell' => 'SN',
    'ssh' => 'SH',
    'anytls' => 'A',
    _ => '?',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final chip = Container(
      decoration: BoxDecoration(
        color: selected
            ? scheme.primary.withValues(alpha: 0.16)
            : scheme.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: selected ? scheme.primary : scheme.outlineVariant,
          width: selected ? 1.4 : 1,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(5, 3, 3, 3),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (selected)
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Icon(Icons.check_circle, size: 13, color: scheme.primary),
            ),
          Container(
            width: 18,
            height: 18,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(4),
              border: Border.all(color: scheme.primary.withValues(alpha: 0.20)),
            ),
            child: Text(
              _typeBadge(node.type),
              style: mono(8.5, color: scheme.primary, weight: 700),
            ),
          ),
          const SizedBox(width: 6),
          Text(node.name, style: display(13, weight: 500)),
          if (onMenu != null)
            InkWell(
              onTap: onMenu,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(3),
                child: Icon(
                  Icons.more_vert,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
          if (onRemove != null)
            InkWell(
              onTap: onRemove,
              customBorder: const CircleBorder(),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: Icon(
                  Icons.close,
                  size: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            )
          else if (onMenu == null)
            const SizedBox(width: 4),
        ],
      ),
    );

    return LongPressDraggable<_DragData>(
      data: _DragData(node.name, fromGroup),
      // 300ms 比默认 500ms 更容易触发；长按后跟手拖动不会被滚动抢走。
      delay: const Duration(milliseconds: 300),
      hapticFeedbackOnStart: true,
      dragAnchorStrategy: childDragAnchorStrategy,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.92, child: chip),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: chip),
      child: GestureDetector(
        onSecondaryTapDown: (details) async {
          final choice = await showMenu<String>(
            context: context,
            position: RelativeRect.fromLTRB(
              details.globalPosition.dx,
              details.globalPosition.dy,
              details.globalPosition.dx,
              details.globalPosition.dy,
            ),
            items: const [
              PopupMenuItem(value: 'edit', child: Text('编辑节点')),
              PopupMenuItem(value: 'move', child: Text('移动到…')),
              PopupMenuItem(value: 'delete', child: Text('删除节点')),
            ],
          );
          switch (choice) {
            case 'edit':
              onOpen();
            case 'move':
              onMove();
            case 'delete':
              onDelete();
          }
        },
        child: Tooltip(
          message: onSelect != null
              ? '点按 = 让「$fromGroup」改用这个节点\n⋮ 打开操作；长按可拖到别的组'
              : '${node.type} · ${node.subtitle}\n点按编辑，长按可拖到别的组',
          // 关键：默认 triggerMode 是 longPress，会和 LongPressDraggable 抢手势，
          // 结果长按只弹提示、拖不起来。这里改成只能代码触发。
          triggerMode: TooltipTriggerMode.manual,
          child: InkWell(
            onTap: onSelect ?? onOpen,
            borderRadius: BorderRadius.circular(10),
            child: chip,
          ),
        ),
      ),
    );
  }
}

/// 新建策略组的结果。
class _NewGroupSpec {
  const _NewGroupSpec({required this.name, required this.type});

  final String name;
  final String type;
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
          TextField(
            controller: _ctrl,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: '组名',
              border: OutlineInputBorder(),
            ),
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
            _NewGroupSpec(name: _ctrl.text.trim(), type: _type),
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
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '组名',
                helperText: '改名会同步规则与其它组里的引用',
                border: OutlineInputBorder(),
              ),
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
              TextField(
                controller: _urlCtrl,
                decoration: const InputDecoration(
                  labelText: '测速 URL',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _intervalCtrl,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: '间隔（秒）',
                  border: OutlineInputBorder(),
                ),
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
