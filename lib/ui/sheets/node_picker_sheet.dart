import 'package:material_ui/material_ui.dart';

import '../../core/edit/member_picker.dart';
import '../../core/model/profile.dart';
import '../chips.dart';
import '../theme.dart';
import '../widgets/select_sheet.dart';
import 'picker_sheet.dart';

/// 选择面板的分区，顺序固定：系统策略 → 节点 → 策略组。
enum NodePickerSection { builtin, node, group }

/// 选择面板的一行候选。
class NodePickerEntry {
  const NodePickerEntry({
    required this.name,
    required this.section,
    this.isGroup = false,
    this.note,
    this.inside = false,
  });

  final String name;
  final NodePickerSection section;

  /// true = 策略组，false = 节点 / 内置出站。
  final bool isGroup;

  /// 行尾小字（例如 REJECT-DROP 的「不常用」）。
  final String? note;

  /// 已经在组里：整行置灰、不可点。
  final bool inside;
}

/// 把 [Profile] 的成员候选展开成选择面板的行数据。
///
/// 数据来自 [memberCandidates]，分区顺序按 [NodePickerSection] 固定。
List<NodePickerEntry> nodePickerEntries(
  Profile profile, {
  required String groupName,
  required Iterable<String> members,
  bool includeBuiltins = true,
  bool includeGroups = true,
}) {
  final candidates = memberCandidates(
    profile,
    groupName: groupName,
    members: members,
  );
  return [
    if (includeBuiltins)
      for (final candidate in candidates)
        if (candidate.isBuiltin)
          NodePickerEntry(
            name: candidate.name,
            section: NodePickerSection.builtin,
            note: candidate.note,
            inside: candidate.inGroup,
          ),
    for (final candidate in candidates)
      if (!candidate.isBuiltin && !candidate.isGroup)
        NodePickerEntry(
          name: candidate.name,
          section: NodePickerSection.node,
          inside: candidate.inGroup,
        ),
    for (final candidate in candidates)
      if (includeGroups && candidate.isGroup)
        NodePickerEntry(
          name: candidate.name,
          section: NodePickerSection.group,
          isGroup: true,
          inside: candidate.inGroup,
        ),
  ];
}

/// 打开统一的选择面板，返回选中的成员名（按点选顺序），取消返回 null。
Future<List<String>?> showNodePickerSheet(
  BuildContext context, {
  required Profile profile,
  required String groupName,
  required Iterable<String> members,
  String title = '选择要加入的节点',
  String? subtitle,
  String confirmVerb = '加入',
  bool includeBuiltins = true,
  bool includeGroups = true,
  VoidCallback? onCreateNode,
}) {
  return showSelectSheet<List<String>>(
    context,
    title: title,
    subtitle: subtitle ?? '向「$groupName」批量添加成员',
    body: (_) => _NodePickerSheet(
      profile: profile,
      groupName: groupName,
      members: members,
      confirmVerb: confirmVerb,
      includeBuiltins: includeBuiltins,
      includeGroups: includeGroups,
      onCreateNode: onCreateNode,
    ),
  );
}

class _NodePickerSheet extends StatefulWidget {
  const _NodePickerSheet({
    required this.profile,
    required this.groupName,
    required this.members,
    required this.confirmVerb,
    required this.includeBuiltins,
    this.includeGroups = true,
    this.onCreateNode,
  });

  final Profile profile;
  final String groupName;
  final Iterable<String> members;
  final String confirmVerb;
  final bool includeBuiltins;
  final bool includeGroups;
  final VoidCallback? onCreateNode;

  @override
  State<_NodePickerSheet> createState() => _NodePickerSheetState();
}

class _NodePickerSheetState extends State<_NodePickerSheet> {
  final List<String> _picked = <String>[];

  List<NodePickerEntry> get _entries => nodePickerEntries(
    widget.profile,
    groupName: widget.groupName,
    members: widget.members,
    includeBuiltins: widget.includeBuiltins,
    includeGroups: widget.includeGroups,
  );

  void _toggle(NodePickerEntry entry) {
    if (entry.inside) return;
    setState(() {
      if (!_picked.remove(entry.name)) _picked.add(entry.name);
    });
  }

  void _selectAll() {
    setState(() {
      for (final entry in _entries) {
        if (!entry.inside && !_picked.contains(entry.name)) {
          _picked.add(entry.name);
        }
      }
    });
  }

  void _invert() {
    setState(() {
      for (final entry in _entries) {
        if (entry.inside) continue;
        if (!_picked.remove(entry.name)) _picked.add(entry.name);
      }
    });
  }

  void _clear() => setState(_picked.clear);

  PickerSheetSection? _sectionOf(NodePickerSection section, String label) {
    final rows = [
      for (final item in _entries)
        if (item.section == section)
          PickerSheetRow(
            searchText: item.name,
            title: NameChip(
              name: item.name,
              icon: item.section == NodePickerSection.builtin
                  ? builtinIcon(item.name)
                  : item.isGroup
                  ? Icons.account_tree_outlined
                  : Icons.dns_outlined,
              subtitle: item.inside
                  ? '已在组内'
                  : item.note ??
                        (item.section == NodePickerSection.builtin
                            ? '系统策略'
                            : null),
            ),
            selected: _picked.contains(item.name),
            enabled: !item.inside,
            onTap: () => _toggle(item),
          ),
    ];
    if (rows.isEmpty) return null;
    return PickerSheetSection(label: label, rows: rows);
  }

  @override
  Widget build(BuildContext context) {
    final sections = [
      if (widget.includeBuiltins)
        ?_sectionOf(NodePickerSection.builtin, '系统策略'),
      ?_sectionOf(NodePickerSection.node, '节点'),
      if (widget.includeGroups) ?_sectionOf(NodePickerSection.group, '策略组'),
    ];
    return PickerSheetScaffold(
      searchHint: widget.includeGroups ? '搜索节点或策略组' : '搜索节点',
      sections: sections,
      selectedCount: _picked.length,
      onSelectAll: _selectAll,
      onInvert: _invert,
      onClear: _clear,
      emptyHint: widget.profile.proxies.isEmpty
          ? '还没有节点：点左下角「添加节点」先建一个。'
          : '没有匹配的节点或策略组',
      footer: Row(
        children: [
          if (widget.onCreateNode != null)
            TextButton.icon(
              onPressed: widget.onCreateNode,
              icon: const Icon(Icons.add, size: 18),
              label: const Text('添加节点'),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: Insets.md),
          FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(List<String>.of(_picked)),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('${widget.confirmVerb} ${_picked.length} 个'),
          ),
        ],
      ),
    );
  }
}
