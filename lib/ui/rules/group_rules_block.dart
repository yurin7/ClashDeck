import 'package:material_ui/material_ui.dart';

import '../../core/edit/config_ops.dart';
import '../../core/edit/rule_targets.dart';
import '../../core/model/profile.dart';
import '../../core/model/rule_types.dart';
import '../../state/editor_state.dart';
import '../rule_edit_dialog.dart';
import '../rule_picker_sheet.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/target_selector_field.dart';
import '../chips.dart';
import 'rule_row_card.dart';
import '../widgets/app_ink.dart';
import '../widgets/delete_confirm.dart';

/// 组卡与系统策略卡共用的「规则区块」。
///
/// 按 `rule.target == target` 反查规则：计数头 + 展开 + 「添加已有规则 /
/// 新建一条」，行本身复用 [RuleRowCard] 的紧凑模式，点开即编辑。
/// 拖拽「本组规则」里的胶囊时携带的数据；组卡用 [DragTarget] 接住它。
class RuleDragData {
  const RuleDragData(this.rule);

  final RuleEntry rule;
}

class GroupRulesBlock extends StatefulWidget {
  const GroupRulesBlock({
    super.key,
    required this.state,
    required this.target,
    this.title = '本组规则',
    this.newRuleLabel = '新建一条',
  });

  final EditorState state;

  /// 规则目标：策略组名，或 `DIRECT` / `REJECT` 这类系统策略。
  final String target;

  final String title;

  /// 新建按钮文案；系统策略卡上用「添加规则」。
  final String newRuleLabel;

  @override
  State<GroupRulesBlock> createState() => _GroupRulesBlockState();
}

class _GroupRulesBlockState extends State<GroupRulesBlock> {
  bool _expanded = false;

  /// 当前左滑露出「删除」的规则 index。
  int? _swipedRule;

  List<RuleEntry> get _rules => [
    for (final rule in widget.state.profile.rules)
      if (rule.target == widget.target) rule,
  ];

  void _fail() {
    if (!mounted) return;
    showToast(context, '这条规则没写进去，请检查配置');
  }

  /// 从已有规则里批量挑，挑中的改到本目标下。
  Future<void> _addExisting() async {
    final profile = widget.state.profile;
    final picked = await showRulePickerSheet(
      context,
      group: widget.target,
      candidates: rulesAssignableTo(profile, widget.target),
    );
    if (picked == null || picked.isEmpty) return;
    final rules = profile.rules;
    if (!widget.state.apply(
      (doc) => retargetRules(
        doc,
        rules,
        picked.map((rule) => rule.index),
        widget.target,
      ),
    )) {
      _fail();
      return;
    }
    if (!mounted) return;
    setState(() {});
    final ruleSets = picked.where((rule) => rule.type == 'RULE-SET').length;
    showToast(
      context,
      ruleSets == 0
          ? '已把 ${picked.length} 条规则挂到「${widget.target}」'
          : '已把 ${picked.length} 条规则挂到「${widget.target}」（含 $ruleSets 条规则集）',
    );
  }

  /// 行尾换组图标：直接开目标选择面板，选完即改。
  Future<void> _moveRule(RuleEntry rule) async {
    final targets = ruleTargetsFor(
      widget.state.profile,
      preferred: rule.target,
    ).primary;
    final picked = await showTargetPickerSheet(
      context,
      title: '换到别的组',
      subtitle: rule.raw,
      options: targets,
      current: rule.target,
    );
    if (picked == null || picked == rule.target || !mounted) return;
    if (!widget.state.apply(
      (doc) =>
          ConfigOps.updateRule(doc, rule.index, ruleWithTarget(rule, picked)),
    )) {
      _fail();
      return;
    }
    if (!mounted) return;
    setState(() {});
    showToast(context, '已把这条规则挂到「$picked」');
  }

  Future<void> _edit({RuleEntry? initial}) async {
    final targets = ruleTargetsFor(
      widget.state.profile,
      preferred: initial?.target ?? widget.target,
    );
    final draft = await showRuleEditDialog(
      context,
      initialType: initial?.type,
      initialPayload: initial?.payload,
      initialTarget: initial?.target ?? widget.target,
      initialNoResolve: initial?.noResolve ?? false,
      targets: targets.primary,
      otherBuiltins: targets.otherBuiltins,
      isNew: initial == null,
      // 编辑已有规则时，标题行删除入口与左滑删除共用这一套确认。
      onDelete: initial == null ? null : () => _delete(initial),
    );
    if (draft == null || !mounted) return;
    final parts = <String>[
      draft.type,
      if (!kTerminalRuleTypes.contains(draft.type)) draft.payload,
      draft.target,
      if (draft.noResolve) 'no-resolve',
      ...?initial?.options.where((o) => o != 'no-resolve'),
    ];
    final line = parts.where((p) => p.isNotEmpty).join(',');
    final ok = initial == null
        ? widget.state.addRule(line)
        : widget.state.apply(
            (d) => ConfigOps.updateRule(d, initial.index, line),
          );
    if (!ok) {
      _fail();
      return;
    }
    if (mounted) setState(() {});
  }

  /// 删除一条规则；规则行左滑与编辑弹窗里的删除共用它。
  Future<bool> _delete(RuleEntry rule) async {
    if (!mounted) return false;
    final confirmed = await confirmDelete(
      context,
      title: '删除这条规则？',
      message: '这条规则会从当前配置里移除，删掉后只能重新添加。',
    );
    if (!confirmed || !mounted) return false;
    if (!widget.state.deleteRule(rule.index)) {
      _fail();
      return false;
    }
    if (mounted) setState(() {});
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final rules = _rules;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: Insets.md),
        const Hairline(),
        AppInkWell(
          borderRadius: BorderRadius.circular(Radiuses.xs),
          onTap: rules.isEmpty
              ? null
              : () => setState(() => _expanded = !_expanded),
          child: Padding(
            padding: const EdgeInsets.only(top: Insets.md, right: Insets.sm),
            child: Row(
              children: [
                Icon(
                  Icons.rule_outlined,
                  size: 16,
                  color: scheme.onSurfaceVariant,
                ),
                const SizedBox(width: Insets.sm),
                Text(
                  '${widget.title} ${rules.length}',
                  style: mono(12, color: scheme.onSurfaceVariant),
                ),
                if (rules.isEmpty) ...[
                  const SizedBox(width: Insets.sm),
                  Text('还没有规则', style: Theme.of(context).textTheme.labelMedium),
                ],
                const Spacer(),
                if (rules.isNotEmpty)
                  AnimatedRotation(
                    turns: _expanded ? 0.5 : 0,
                    duration: motion.arrow,
                    curve: motion.enter,
                    child: Icon(
                      Icons.expand_more,
                      size: 18,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
        ),
        AnimatedSize(
          duration: motion.expand,
          curve: motion.enter,
          alignment: Alignment.topCenter,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_expanded && rules.isNotEmpty) ...[
                const SizedBox(height: Insets.xs),
                for (final rule in rules)
                  Padding(
                    key: ValueKey('group-rule-${rule.index}'),
                    padding: const EdgeInsets.only(bottom: Insets.xs),
                    child: SlidableRow(
                      open: _swipedRule == rule.index,
                      onOpenChanged: (open) => setState(
                        () => _swipedRule = open ? rule.index : null,
                      ),
                      actionLabel: '删除',
                      // RuleChip 是 kChipRadius 的胶囊，红块跟着裁成同一圆角。
                      borderRadius: BorderRadius.circular(kChipRadius),
                      onAction: () => _delete(rule),
                      child: LongPressDraggable<RuleDragData>(
                        data: RuleDragData(rule),
                        feedback: Material(
                          color: Colors.transparent,
                          child: SizedBox(
                            width: 240,
                            child: RuleChip(rule: rule),
                          ),
                        ),
                        child: RuleChip(
                          rule: rule,
                          onTap: () => _edit(initial: rule),
                          trailing: IconButton(
                            tooltip: '换到别的组',
                            visualDensity: VisualDensity.compact,
                            constraints: const BoxConstraints(
                              minWidth: 44,
                              minHeight: 44,
                            ),
                            onPressed: () => _moveRule(rule),
                            icon: const Icon(Icons.swap_horiz, size: 16),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
              if (_expanded || rules.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(
                    top: Insets.xs,
                    right: Insets.sm,
                  ),
                  child: Row(
                    children: [
                      TextButton.icon(
                        onPressed: _addExisting,
                        icon: const Icon(Icons.playlist_add, size: 16),
                        label: const Text('添加已有规则'),
                      ),
                      TextButton.icon(
                        onPressed: () => _edit(),
                        icon: const Icon(Icons.add, size: 16),
                        label: Text(widget.newRuleLabel),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}
