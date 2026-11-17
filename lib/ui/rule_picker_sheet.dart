import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/model/profile.dart';
import '../core/yaml/yaml_doc.dart';
import 'theme.dart';
import 'widgets.dart';

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

/// 「添加规则」面板：像选节点那样批量挑已有规则，挑中的挂到本组。
Future<List<RuleEntry>?> showRulePickerSheet(
  BuildContext context, {
  required String group,
  required List<RuleEntry> candidates,
}) {
  if (candidates.isEmpty) return Future.value(const <RuleEntry>[]);
  return showGeneralDialog<List<RuleEntry>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: '选择规则',
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => const SizedBox.shrink(),
    transitionBuilder: (dialogContext, animation, _, _) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: _RulePickerSheet(group: group, candidates: candidates),
        ),
      );
    },
  );
}

class _RulePickerSheet extends StatefulWidget {
  const _RulePickerSheet({required this.group, required this.candidates});

  final String group;
  final List<RuleEntry> candidates;

  @override
  State<_RulePickerSheet> createState() => _RulePickerSheetState();
}

class _RulePickerSheetState extends State<_RulePickerSheet> {
  final Set<int> _picked = {};

  List<RuleEntry> get _visible {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return widget.candidates;
    return [
      for (final rule in widget.candidates)
        if (rule.raw.toLowerCase().contains(keyword)) rule,
    ];
  }

  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(RuleEntry rule) {
    setState(() {
      if (!_picked.remove(rule.index)) _picked.add(rule.index);
    });
  }

  void _selectAll() {
    setState(() {
      for (final rule in _visible) {
        _picked.add(rule.index);
      }
    });
  }

  void _clear() => setState(_picked.clear);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final visible = _visible;
    final picked = [
      for (final r in widget.candidates)
        if (_picked.contains(r.index)) r,
    ];

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Radiuses.lg),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.78,
              maxWidth: 520,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.xl,
                    Insets.xl,
                    Insets.xl,
                    Insets.sm,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '添加规则到「${widget.group}」',
                        style: display(17, weight: 600),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '从配置里已有的规则中挑，选中的应用后会改到本组名下。',
                        style: hintStyle(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
                  child: TextField(
                    controller: _search,
                    onChanged: (value) => setState(() => _query = value),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: '搜索规则',
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.xl,
                    Insets.sm,
                    Insets.xl,
                    0,
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: _selectAll,
                        child: const Text('全选'),
                      ),
                      TextButton(onPressed: _clear, child: const Text('清空')),
                      const Spacer(),
                      Text(
                        '已选 ${picked.length} / ${widget.candidates.length}',
                        style: hintStyle(context),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView.builder(
                    shrinkWrap: true,
                    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
                    itemCount: visible.length,
                    itemBuilder: (_, i) {
                      final rule = visible[i];
                      return CheckboxListTile(
                        dense: true,
                        value: _picked.contains(rule.index),
                        onChanged: (_) => _toggle(rule),
                        controlAffinity: ListTileControlAffinity.leading,
                        title: Row(
                          children: [
                            Expanded(
                              child: Text(
                                rule.payload.isEmpty
                                    ? rule.type
                                    : '${rule.type} · ${rule.payload}',
                                style: mono(12, color: scheme.onSurface),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (rule.type == 'RULE-SET') ...[
                              const SizedBox(width: Insets.sm),
                              const Pill(label: '规则集'),
                            ],
                          ],
                        ),
                        subtitle: Text(
                          '现在指向 ${rule.target}',
                          style: hintStyle(context),
                        ),
                      );
                    },
                  ),
                ),
                const Hairline(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.xl,
                    Insets.sm,
                    Insets.xl,
                    Insets.sm,
                  ),
                  child: Row(
                    children: [
                      TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('取消'),
                      ),
                      const Spacer(),
                      FilledButton(
                        onPressed: picked.isEmpty
                            ? null
                            : () => Navigator.of(context).pop(picked),
                        child: Text('添加 ${picked.length} 条'),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
