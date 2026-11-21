import 'package:material_ui/material_ui.dart';

import '../../core/edit/rule_labels.dart';
import '../../core/model/profile.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/app_ink.dart';

const _directColor = Color(0xFF3FB950);

/// 规则行胶囊卡（0.3.4 信息层级）。
///
/// 左侧 4dp 竖色条按「规则目标」着色：DIRECT 绿、REJECT 红、策略组紫、
/// 其它灰；主标题只放规则值/规则集显示名，类型小标签在行尾；第二行是
/// 「→ 目标」和附加标记。行内只显示一行，完整名字与 payload 走点击详情。
///
/// 拖动手柄由调用方通过 [dragHandle] 传入（复用 `ReorderableDragStartListener`），
/// 卡片内部不自建手柄：折叠的分区不构建卡片，自然也不会出现手柄。
/// [compact] 用于组卡「本组规则」这类窄区块：只留色条 + 标题 + 菜单。
class RuleRowCard extends StatelessWidget {
  const RuleRowCard({
    super.key,
    required this.rule,
    required this.onTap,
    required this.onEdit,
    required this.onMoveToGroup,
    this.dragHandle,
    this.onRefresh,
    this.trailing,
    this.onDelete,
    this.compact = false,
    this.groupNames = const <String>{},
  });

  final RuleEntry rule;

  /// 排序手柄。
  final Widget? dragHandle;

  /// 点整行：打开详情（完整名字 / payload）。
  final VoidCallback onTap;

  final VoidCallback onEdit;

  /// 行尾「换组」图标：直接打开目标选择面板，选完即改。
  final VoidCallback onMoveToGroup;

  /// 「更新规则集」；为 null 时没有这个动作。
  final VoidCallback? onRefresh;

  /// 副标题行尾的附加信息（在线规则集的缓存时间 / 更新失败标记）。
  final Widget? trailing;
  final VoidCallback? onDelete;

  final bool compact;

  /// 配置里已有的策略组名，用来把「目标是组」染成主色。
  final Set<String> groupNames;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final targetColor = _targetColor(scheme, rule.target);

    if (!compact && Theme.of(context).platform == TargetPlatform.windows) {
      return _desktopRow(context, scheme, targetColor);
    }

    return Material(
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: AppInkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 44 : 56),
          padding: const EdgeInsets.fromLTRB(
            Insets.sm,
            Insets.xs,
            Insets.sm,
            Insets.xs,
          ),
          child: Row(
            children: [
              // 4dp 目标色条：比图标更安静，也更容易扫读一列规则。
              _TargetStripe(color: targetColor, height: compact ? 28 : 34),
              SizedBox(width: compact ? Insets.sm : Insets.md),
              Expanded(child: _texts(context, scheme, targetColor)),
              if (!compact) ...[
                const SizedBox(width: Insets.sm),
                _TypeTag(label: rule.type),
                const SizedBox(width: Insets.xs),
              ],
              if (onRefresh != null)
                IconButton(
                  tooltip: '更新规则集',
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(
                    minWidth: 44,
                    minHeight: 44,
                  ),
                  onPressed: onRefresh,
                  icon: Icon(
                    Icons.refresh,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              if (!compact) _swapButton(context),
              ?dragHandle,
            ],
          ),
        ),
      ),
    );
  }

  Widget _desktopRow(
    BuildContext context,
    ColorScheme scheme,
    Color targetColor,
  ) {
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.sm),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.65)),
      ),
      clipBehavior: Clip.antiAlias,
      child: AppInkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radiuses.sm),
        hoverColor: scheme.primary.withValues(alpha: 0.07),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 56),
          child: _DesktopRuleColumns(
            stripe: _TargetStripe(color: targetColor, height: 32),
            match: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  ruleDisplayTitle(rule),
                  style: mono(13.5, weight: 650),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        rule.type,
                        style: mono(10.5, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (rule.noResolve)
                      Padding(
                        padding: const EdgeInsets.only(left: Insets.sm),
                        child: Tooltip(
                          message: '不解析域名（no-resolve）',
                          child: Icon(
                            Icons.dns_outlined,
                            size: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                    if (trailing != null) ...[
                      const SizedBox(width: Insets.md),
                      Flexible(flex: 2, child: trailing!),
                    ],
                  ],
                ),
              ],
            ),
            target: Tooltip(
              message: rule.target,
              child: _TargetChip(
                label: '→ ${rule.target}',
                color: targetColor,
                desktop: true,
              ),
            ),
            actions: Row(
              children: [
                if (onRefresh == null)
                  const SizedBox(width: _DesktopRuleColumns.buttonWidth)
                else
                  _desktopButton(
                    tooltip: '更新规则集',
                    icon: Icons.refresh,
                    onPressed: onRefresh,
                  ),
                _desktopButton(
                  tooltip: '换到别的组',
                  icon: Icons.swap_horiz,
                  onPressed: onMoveToGroup,
                ),
                SizedBox(
                  width: _DesktopRuleColumns.buttonWidth,
                  child: PopupMenuButton<String>(
                    tooltip: '规则操作',
                    padding: EdgeInsets.zero,
                    icon: const Icon(Icons.more_horiz, size: 18),
                    onSelected: (action) =>
                        action == 'edit' ? onEdit() : onDelete?.call(),
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      if (onDelete != null)
                        const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                ),
                Expanded(child: dragHandle ?? const SizedBox.shrink()),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _desktopButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) => SizedBox(
    width: _DesktopRuleColumns.buttonWidth,
    child: IconButton(
      tooltip: tooltip,
      padding: EdgeInsets.zero,
      onPressed: onPressed,
      icon: Icon(icon, size: 18),
    ),
  );

  Widget _texts(BuildContext context, ColorScheme scheme, Color targetColor) {
    final title = Text(
      ruleDisplayTitle(rule),
      style: mono(compact ? 12.5 : 13.5, weight: 700),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );

    if (compact) {
      return Row(children: [Expanded(child: title)]);
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        title,
        const SizedBox(height: 4),
        Row(
          children: [
            _TargetChip(label: '→ ${rule.target}', color: targetColor),
            if (rule.isTerminal) ...[
              const SizedBox(width: Insets.sm),
              Pill(
                label: '兜底',
                color: context.semantic.warn,
                icon: Icons.flag_outlined,
                dense: true,
              ),
            ],
            if (rule.noResolve) ...[
              const SizedBox(width: Insets.sm),
              const Pill(label: 'no-resolve', dense: true),
            ],
            if (trailing != null) ...[
              const SizedBox(width: Insets.sm),
              Flexible(
                child: Align(alignment: Alignment.centerLeft, child: trailing!),
              ),
            ],
          ],
        ),
      ],
    );
  }

  /// 换组：一点就开目标选择面板，选完即改；没有二次确认。
  Widget _swapButton(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: '换到别的组',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      onPressed: onMoveToGroup,
      icon: Icon(Icons.swap_horiz, size: 18, color: scheme.onSurfaceVariant),
    );
  }

  /// 目标色：DIRECT 绿、REJECT 红、策略组主色、其它（PASS/GLOBAL/未知）灰。
  Color _targetColor(ColorScheme scheme, String target) {
    final name = target.trim();
    if (name == 'DIRECT') return _directColor;
    if (name == 'REJECT' || name == 'REJECT-DROP') return scheme.error;
    if (groupNames.contains(name)) return scheme.primary;
    return scheme.outline;
  }
}

/// 桌面规则列表的列标题，与规则行使用相同的列宽。
class DesktopRuleTableHeader extends StatelessWidget {
  const DesktopRuleTableHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final style = hintStyle(context)?.copyWith(fontWeight: FontWeight.w600);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: _DesktopRuleColumns(
        match: Text('匹配条件', style: style),
        target: Text('目标策略', style: style),
        actions: Center(child: Text('操作', style: style)),
      ),
    );
  }
}

class DesktopRuleLegend extends StatelessWidget {
  const DesktopRuleLegend({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Wrap(
      spacing: Insets.lg,
      runSpacing: Insets.xs,
      children: [
        for (final (label, color) in [
          ('策略组', scheme.primary),
          ('直连', _directColor),
          ('拒绝', scheme.error),
        ])
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              _TargetStripe(color: color, height: 12),
              const SizedBox(width: 6),
              Text(label, style: hintStyle(context)),
            ],
          ),
      ],
    );
  }
}

class _DesktopRuleColumns extends StatelessWidget {
  const _DesktopRuleColumns({
    required this.match,
    required this.target,
    required this.actions,
    this.stripe,
  });

  static const buttonWidth = 34.0;
  static const _actionsWidth = buttonWidth * 3 + 44;
  final Widget match;
  final Widget target;
  final Widget actions;
  final Widget? stripe;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.md),
      child: Row(
        children: [
          SizedBox(width: 4, child: stripe),
          const SizedBox(width: Insets.md),
          Expanded(child: match),
          const SizedBox(width: Insets.md),
          SizedBox(
            width: 132,
            child: Align(alignment: Alignment.centerLeft, child: target),
          ),
          const SizedBox(width: Insets.sm),
          SizedBox(width: _actionsWidth, child: actions),
        ],
      ),
    );
  }
}

class _TargetStripe extends StatelessWidget {
  const _TargetStripe({required this.color, required this.height});

  final Color color;
  final double height;

  @override
  Widget build(BuildContext context) => Container(
    width: 4,
    height: height,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(2),
    ),
  );
}

/// 行尾类型小标签：`RULE-SET` / `GEOSITE` / `DOMAIN-SUFFIX`。
class _TypeTag extends StatelessWidget {
  const _TypeTag({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.7)),
      ),
      child: Text(
        label,
        style: mono(
          9,
          color: scheme.onSurfaceVariant,
          weight: 600,
          letterSpacing: 0.2,
        ),
        maxLines: 1,
      ),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({
    required this.label,
    required this.color,
    this.desktop = false,
  });

  final String label;
  final Color color;
  final bool desktop;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: desktop ? 8 : 6,
        vertical: desktop ? 4 : 1.5,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Text(
          label,
          style: mono(desktop ? 11.5 : 10, color: color, weight: 600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}
