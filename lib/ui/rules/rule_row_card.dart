import 'package:material_ui/material_ui.dart';

import '../../core/edit/rule_labels.dart';
import '../../core/model/profile.dart';
import '../../core/model/rule_zone.dart';
import '../theme.dart';
import '../widgets.dart';

/// 规则行胶囊卡。
///
/// 左侧是 32×32 的分区图标，中间主标题（能认出的名字）+ 副标题
/// （类型小标签、「→ 目标」小胶囊、缓存信息），行尾 `chevron_right`、
/// `⋮` 菜单与拖动手柄。
///
/// 拖动手柄由调用方通过 [dragHandle] 传入（复用 `ReorderableDragStartListener`），
/// 卡片内部不自建手柄：折叠的分区不构建卡片，自然也不会出现手柄。
/// [compact] 用于组卡「本组规则」这类窄区块：只留图标 + 标题 + 菜单。
class RuleRowCard extends StatelessWidget {
  const RuleRowCard({
    super.key,
    required this.rule,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    this.dragHandle,
    this.onMoveToGroup,
    this.onRefresh,
    this.trailing,
    this.compact = false,
  });

  final RuleEntry rule;

  /// 排序手柄，固定在本行最右侧。
  final Widget? dragHandle;

  /// 点整行：编辑这条规则。
  final VoidCallback onTap;

  final VoidCallback onEdit;

  /// 「改挂到组」；为 null 时菜单不出现这一项（紧凑模式不需要）。
  final VoidCallback? onMoveToGroup;

  /// 「更新规则集」；为 null 时菜单不出现这一项。
  final VoidCallback? onRefresh;

  final VoidCallback onDelete;

  /// 副标题行尾的附加信息（在线规则集的缓存时间 / 更新失败标记）。
  final Widget? trailing;

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentOf(scheme, rule);

    return Material(
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(17),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.55)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: compact ? 44 : 54),
          padding: const EdgeInsets.fromLTRB(
            Insets.md,
            Insets.xs,
            Insets.sm,
            Insets.xs,
          ),
          child: Row(
            children: [
              _TypeBadge(
                color: accent.color,
                icon: accent.icon,
                size: compact ? 26 : 32,
              ),
              SizedBox(width: compact ? Insets.sm : Insets.md),
              Expanded(child: _texts(context, scheme, accent.color)),
              if (!compact)
                Icon(Icons.chevron_right, size: 18, color: scheme.outline),
              _menu(context, scheme),
              ?dragHandle,
            ],
          ),
        ),
      ),
    );
  }

  Widget _texts(BuildContext context, ColorScheme scheme, Color accent) {
    final title = Text(
      ruleTitleOf(rule),
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
        Row(
          children: [
            Text(
              rule.type,
              style: mono(
                9.5,
                color: scheme.onSurfaceVariant,
                weight: 600,
                letterSpacing: 0.3,
              ),
              maxLines: 1,
            ),
            const SizedBox(width: Insets.sm),
            Expanded(child: title),
          ],
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            _TargetChip(label: '→ ${rule.target}', color: accent),
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

  Widget _menu(BuildContext context, ColorScheme scheme) {
    return PopupMenuButton<_RowAction>(
      tooltip: '更多操作',
      padding: EdgeInsets.zero,
      icon: Icon(Icons.more_vert, size: 18, color: scheme.onSurfaceVariant),
      onSelected: (action) {
        switch (action) {
          case _RowAction.edit:
            onEdit();
          case _RowAction.move:
            onMoveToGroup?.call();
          case _RowAction.refresh:
            onRefresh?.call();
          case _RowAction.delete:
            onDelete();
        }
      },
      itemBuilder: (_) => [
        PopupMenuItem<_RowAction>(
          value: _RowAction.edit,
          height: 40,
          child: _menuRow(Icons.edit_outlined, '编辑', scheme.onSurface),
        ),
        if (onMoveToGroup != null)
          PopupMenuItem<_RowAction>(
            value: _RowAction.move,
            height: 40,
            child: _menuRow(Icons.swap_horiz, '改挂到组', scheme.onSurface),
          ),
        if (onRefresh != null)
          PopupMenuItem<_RowAction>(
            value: _RowAction.refresh,
            height: 40,
            child: _menuRow(Icons.refresh, '更新规则集', scheme.onSurface),
          ),
        PopupMenuItem<_RowAction>(
          value: _RowAction.delete,
          height: 40,
          child: _menuRow(Icons.delete_outline, '删除', scheme.error),
        ),
      ],
    );
  }

  Widget _menuRow(IconData icon, String label, Color color) {
    return Row(
      children: [
        Icon(icon, size: 16, color: color),
        const SizedBox(width: Insets.sm),
        Text(label, style: TextStyle(color: color)),
      ],
    );
  }
}

enum _RowAction { edit, move, refresh, delete }

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({
    required this.color,
    required this.icon,
    required this.size,
  });

  final Color color;
  final IconData icon;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.32),
      ),
      child: Icon(icon, size: size * 0.56, color: color),
    );
  }
}

class _TargetChip extends StatelessWidget {
  const _TargetChip({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(5),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 132),
        child: Text(
          label,
          style: mono(10, color: color, weight: 600),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
    );
  }
}

({Color color, IconData icon}) _accentOf(ColorScheme scheme, RuleEntry rule) {
  return switch (ruleZoneOf(rule.raw)) {
    RuleZone.local => (color: scheme.primary, icon: Icons.dns_outlined),
    RuleZone.online => (color: scheme.tertiary, icon: Icons.cloud_outlined),
    RuleZone.geo => (color: scheme.secondary, icon: Icons.public),
    RuleZone.terminal => (color: scheme.error, icon: Icons.flag_outlined),
  };
}
