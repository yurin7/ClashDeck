import 'package:material_ui/material_ui.dart';

/// 打开一个带统一过渡动画的对话框。
///
/// 和直接 `showDialog` 的区别只有动效：淡入 + 轻微上滑 + 0.96→1 的缩放，
/// 关闭时反向播放。语义完全不变——`barrierDismissible`、返回类型、`pageBuilder`
/// 都和原来的 `showDialog` 一一对应，确认类弹窗显式传 `false` 依然阻断。
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    useRootNavigator: useRootNavigator,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, _, _) => builder(ctx),
    transitionBuilder: (ctx, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.06),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
