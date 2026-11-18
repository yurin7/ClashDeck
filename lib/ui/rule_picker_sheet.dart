import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/model/profile.dart';
import '../core/yaml/yaml_doc.dart';
import 'chips.dart';
import 'sheets/picker_sheet.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/select_sheet.dart';

/// 把一条规则改写成指向另一个目标组，其余字段原样保留。
String ruleWithTarget(RuleEntry rule, String target) {
  final parts = <String>[
    rule.type,
    if (!rule.isTerminal) rule.payload,
    target,
    ...rule.options,
  ];
  return parts.where((part) => part.isNotEmpty).join(',');
}

/// 批量把若干条规则的目标改成 [target]，返回新文档。
///
/// 索引来自 [Profile.rules]，`updateRule` 是原地替换，所以一个个改也不会串位。
YamlDoc retargetRules(
  YamlDoc doc,
  List<RuleEntry> rules,
  Iterable<int> indexes,
  String target,
) {
  final byIndex = {for (final rule in rules) rule.index: rule};
  var next = doc;
  for (final index in indexes) {
    final rule = byIndex[index];
    if (rule == null || rule.target == target) continue;
    next = ConfigOps.updateRule(next, index, ruleWithTarget(rule, target));
  }
  return next;
}

/// 一个组可用「添加」的规则：别人家的、非兜底规则。
///
/// 兜底（MATCH/FINAL）必须留在最后一条，不参与改目标。
List<RuleEntry> rulesAssignableTo(Profile profile, String group) => [
  for (final rule in profile.rules)
    if (rule.target != group && !rule.isTerminal) rule,
];

/// 「添加规则」面板：与「选择要加入的节点」同一个骨架（PickerSheetScaffold），
/// 行内用 [RuleChip]，选中即整行高亮。
Future<List<RuleEntry>?> showRulePickerSheet(
  BuildContext context, {
  required String group,
  required List<RuleEntry> candidates,
}) {
  if (candidates.isEmpty) return Future.value(const <RuleEntry>[]);
  return showSelectSheet<List<RuleEntry>>(
    context,
    title: '添加规则到「$group」',
    subtitle: '从配置里已有的规则中挑，选中的应用后会改到本组名下',
    body: (_) => _RulePickerSheet(candidates: candidates),
  );
}

class _RulePickerSheet extends StatefulWidget {
  const _RulePickerSheet({required this.candidates});

  final List<RuleEntry> candidates;

  @override
  State<_RulePickerSheet> createState() => _RulePickerSheetState();
}

class _RulePickerSheetState extends State<_RulePickerSheet> {
  final Set<int> _picked = <int>{};

  void _toggle(RuleEntry rule) {
    setState(() {
      if (!_picked.remove(rule.index)) _picked.add(rule.index);
    });
  }

  void _selectAll() => setState(() {
    for (final rule in widget.candidates) {
      _picked.add(rule.index);
    }
  });

  void _invert() => setState(() {
    for (final rule in widget.candidates) {
      if (!_picked.remove(rule.index)) _picked.add(rule.index);
    }
  });

  void _clear() => setState(_picked.clear);

  List<RuleEntry> get _selected => [
    for (final rule in widget.candidates)
      if (_picked.contains(rule.index)) rule,
  ];

  @override
  Widget build(BuildContext context) {
    return PickerSheetScaffold(
      searchHint: '搜索规则',
      sections: [
        PickerSheetSection(
          rows: [
            for (final rule in widget.candidates)
              PickerSheetRow(
                searchText: rule.raw,
                title: RuleChip(rule: rule),
                subtitle: Text(
                  '现在指向 ${rule.target}',
                  style: mono(
                    10.5,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                trailing: rule.type == 'RULE-SET'
                    ? const Pill(label: '规则集', dense: true)
                    : null,
                selected: _picked.contains(rule.index),
                onTap: () => _toggle(rule),
              ),
          ],
        ),
      ],
      selectedCount: _picked.length,
      onSelectAll: _selectAll,
      onInvert: _invert,
      onClear: _clear,
      emptyHint: '没有可挂到本组的规则',
      footer: Row(
        children: [
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
          const SizedBox(width: Insets.md),
          FilledButton(
            onPressed: _picked.isEmpty
                ? null
                : () => Navigator.of(context).pop(_selected),
            style: FilledButton.styleFrom(
              minimumSize: const Size(96, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text('加入 ${_picked.length} 条'),
          ),
        ],
      ),
    );
  }
}
