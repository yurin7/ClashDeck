import 'package:material_ui/material_ui.dart';

import 'sheets.dart';
import 'chips.dart';
import 'theme.dart';

/// 底部上滑选择面板里的一个选项。
class PickerOption<T> {
  const PickerOption(
    this.value,
    this.label, {
    this.subtitle,
    this.icon,
    this.enabled = true,
  });

  final T value;
  final String label;
  final String? subtitle;
  final IconData? icon;
  final bool enabled;
}

/// 从底部滑入的单选面板。
///
/// 原生 `showModalBottomSheet` 的过渡是系统默认的直上直下，列表一多就显得生硬；
/// 这里统一成 240ms `easeOutCubic` 上滑 + 淡入，退出反过来，选中项带高亮底和
/// 对勾，符合「选择策略」这类高频操作的节奏。
Future<T?> showPickerSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<PickerOption<T>> options,
  T? current,
  bool barrierDismissible = true,
  // 胶囊模式：选项排成可换行的 chip（全局出口这类「短名字 + 类型图标」的场景）。
  // 默认仍是整行列表，规则改挂、组内选节点等长文案场景不受影响。
  bool chipMode = false,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => _PickerSheet<T>(
      title: title,
      subtitle: subtitle,
      options: options,
      current: current,
      chipMode: chipMode,
    ),
    transitionBuilder: (context, animation, _, child) {
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
          child: child,
        ),
      );
    },
  );
}

class _PickerSheet<T> extends StatelessWidget {
  const _PickerSheet({
    required this.title,
    required this.subtitle,
    required this.options,
    required this.current,
    required this.chipMode,
  });

  final String title;
  final String? subtitle;
  final List<PickerOption<T>> options;
  final T? current;
  final bool chipMode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = sheetMaxHeight(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(
          left: Insets.sm,
          right: Insets.sm,
          bottom: Insets.sm,
        ),
        child: Material(
          key: const ValueKey('picker-sheet'),
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Insets.xl),
          clipBehavior: Clip.antiAlias,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Insets.sm),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.xl,
                    Insets.md,
                    Insets.lg,
                    Insets.xs,
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title, style: display(17, weight: 700)),
                            if (subtitle != null) ...[
                              const SizedBox(height: 2),
                              Text(subtitle!, style: hintStyle(context)),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: '关闭',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => Navigator.of(context).pop(),
                        icon: const Icon(Icons.close, size: 20),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: chipMode
                      ? SingleChildScrollView(
                          padding: const EdgeInsets.fromLTRB(
                            Insets.lg,
                            0,
                            Insets.lg,
                            Insets.sm,
                          ),
                          child: Wrap(
                            spacing: Insets.sm,
                            runSpacing: Insets.sm,
                            children: [
                              for (final option in options)
                                _PickerChip<T>(
                                  option: option,
                                  selected: option.value == current,
                                  onTap: option.enabled
                                      ? () =>
                                            Navigator.of(context)
                                                .pop(option.value)
                                      : null,
                                ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.only(bottom: Insets.sm),
                          itemCount: options.length,
                          itemBuilder: (context, index) {
                            final option = options[index];
                            final selected = option.value == current;
                            return _PickerRow<T>(
                              option: option,
                              selected: selected,
                              onTap: option.enabled
                                  ? () =>
                                        Navigator.of(context).pop(option.value)
                                  : null,
                            );
                          },
                        ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    0,
                    Insets.lg,
                    Insets.md,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('取消'),
                    ),
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

/// 胶囊模式的选项：直接复用共享的 NameChip，和「全局出口」行同一外观。
class _PickerChip<T> extends StatelessWidget {
  const _PickerChip({required this.option, required this.selected, this.onTap});

  final PickerOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return NameChip(
      name: option.label,
      icon: option.icon,
      subtitle: option.subtitle,
      selected: selected,
      enabled: onTap != null,
      onTap: onTap,
    );
  }
}

class _PickerRow<T> extends StatelessWidget {
  const _PickerRow({required this.option, required this.selected, this.onTap});

  final PickerOption<T> option;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = onTap != null;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: Insets.lg, vertical: 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(Insets.md),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOutCubic,
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm,
            vertical: 3,
          ),
          decoration: BoxDecoration(
            color: selected ? scheme.primary.withValues(alpha: 0.12) : null,
            borderRadius: BorderRadius.circular(Insets.md),
          ),
          child: Row(
            children: [
              Flexible(
                child: NameChip(
                  name: option.label,
                  icon: option.icon,
                  subtitle: option.subtitle,
                  selected: selected,
                  enabled: enabled,
                ),
              ),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}
