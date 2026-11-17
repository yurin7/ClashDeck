import 'package:material_ui/material_ui.dart';

import '../../core/model/profile.dart';
import '../../core/model/rule_zone.dart';
import '../theme.dart';
import '../widgets.dart';

/// 规则行胶囊卡。
///
/// 左侧是 40×40 的分区图标，中间两行文字（类型 + 匹配内容 / `→ target`），
/// 行尾依次是附加信息（[trailing]）、`chevron_right`、`⋮` 菜单和拖动手柄。
///
/// 拖动手柄由调用方通过 [dragHandle] 传入（复用 `ReorderableDragStartListener`），
/// 卡片内部不自建手柄：折叠的分区不构建卡片，自然也不会出现手柄。
class RuleRowCard extends StatelessWidget {
  const RuleRowCard({
    super.key,
    required this.rule,
    required this.dragHandle,
    required this.onTap,
    required this.onEdit,
    required this.onMoveToGroup,
    required this.onDelete,
    this.note,
    this.trailing,
  });

  final RuleEntry rule;

  /// 排序手柄，固定在本行最右侧。
  final Widget dragHandle;

  /// 点整行：编辑这条规则。
  final VoidCallback onTap;

  final VoidCallback onEdit;
  final VoidCallback onMoveToGroup;
  final VoidCallback onDelete;

  /// 主标题右侧的补充说明（`GEOSITE` / `RULE-SET` 的中文名）。
  final String? note;

  /// 行尾附加信息（在线规则集的来源 / 缓存时间 / 更新按钮）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = _accentOf(scheme, rule);

    return Material(
      color: scheme.surfaceContainerHigh,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 58),
          padding: const EdgeInsets.fromLTRB(
            Insets.md,
            Insets.xs,
            Insets.xs,
            Insets.xs,
          ),
          child: Row(
            children: [
              _TypeBadge(color: accent.color, icon: accent.icon),
              const SizedBox(width: Insets.md),
              Expanded(child: _texts(context, scheme, accent.color)),
              ?trailing,
              Icon(Icons.chevron_right, size: 18, color: scheme.outline),
              _menu(context, scheme),
              dragHandle,
            ],
          ),
        ),
      ),
    );
  }

  Widget _texts(BuildContext context, ColorScheme scheme, Color accent) {
    final subtitle = StringBuffer('→ ${rule.target}');
    if (note != null && note!.isNotEmpty) subtitle.write('  ·  $note');
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(
              rule.type,
              style: mono(10.5, color: accent, weight: 700, letterSpacing: 0.6),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(width: Insets.sm),
            Expanded(
              child: Text(
                _primaryLabel,
                style: mono(13, weight: 700),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (rule.isTerminal) ...[
              const SizedBox(width: Insets.xs),
              Pill(
                label: '兜底',
                color: context.semantic.warn,
                icon: Icons.flag_outlined,
                dense: true,
              ),
            ],
            if (rule.noResolve) ...[
              const SizedBox(width: Insets.xs),
              const Pill(label: 'no-resolve', dense: true),
            ],
          ],
        ),
        const SizedBox(height: 3),
        Text(
          subtitle.toString(),
          style: mono(11.5, color: scheme.onSurfaceVariant),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
            onMoveToGroup();
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
        PopupMenuItem<_RowAction>(
          value: _RowAction.move,
          height: 40,
          child: _menuRow(Icons.swap_horiz, '改挂到组', scheme.onSurface),
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

  /// 主标题：本地规则看匹配内容，在线规则集看 provider 名，GEO 看 code，
  /// 兜底规则没有匹配内容，统一显示「所有未匹配流量」。
  String get _primaryLabel {
    if (rule.isTerminal) return '所有未匹配流量';
    final payload = rule.payload;
    return payload.isEmpty ? rule.type : payload;
  }
}

enum _RowAction { edit, move, delete }

class _TypeBadge extends StatelessWidget {
  const _TypeBadge({required this.color, required this.icon});

  final Color color;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Icon(icon, size: 20, color: color),
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
