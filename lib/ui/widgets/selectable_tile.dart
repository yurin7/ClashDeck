import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// 可选行：整行点击切换，选中态 = 高亮底 + 描边 + 行尾 ✓。
///
/// 约定（见 docs/DESIGN_SYSTEM.md）：节点、规则、规则集这类「多选」一律
/// 用高亮行，不再用 Checkbox；只有设置里的开关类保留 Switch。
class SelectableTile extends StatelessWidget {
  const SelectableTile({
    super.key,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.onTap,
    this.padding = const EdgeInsets.symmetric(
      horizontal: Insets.sm,
      vertical: Insets.xs,
    ),
  });

  final Widget title;
  final Widget? subtitle;
  final Widget? leading;

  /// 行尾常驻内容（例如 chip 预览、状态胶囊）；选中勾会追加在它后面。
  final Widget? trailing;

  final bool selected;

  /// 已加入 / 不可选时置灰，点击不回调。
  final bool enabled;

  final VoidCallback? onTap;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.primary;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Material(
        color: selected ? accent.withValues(alpha: 0.12) : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radiuses.sm),
          side: BorderSide(
            color: selected
                ? accent.withValues(alpha: 0.45)
                : Colors.transparent,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: enabled ? onTap : null,
          child: Opacity(
            opacity: enabled ? 1 : 0.55,
            child: Padding(
              padding: padding,
              child: Row(
                children: [
                  if (leading != null) ...[
                    leading!,
                    const SizedBox(width: Insets.sm),
                  ],
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        title,
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          subtitle!,
                        ],
                      ],
                    ),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: Insets.xs),
                    trailing!,
                  ],
                  if (selected) ...[
                    const SizedBox(width: Insets.xs),
                    Icon(Icons.check, size: 16, color: accent),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
