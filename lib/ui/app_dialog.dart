import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// 业务对话框的统一宽度：最宽 520，左右各留 32 的呼吸位。
///
/// 手机（360dp）上算出来是 296，和平板上的 520 都不会贴边；这样「新建组」
/// 「编辑规则」「导入规则」几个弹窗宽度一致，不会一个大一个小。
double dialogWidthOf(BuildContext context) {
  final width = MediaQuery.sizeOf(context).width;
  return math.min(520, math.max(0, width - 64));
}

/// 打开一个带统一过渡动画的对话框。
///
/// 和直接 `showDialog` 的区别只有动效：淡入 + 轻微上滑 + 0.96→1 的缩放，
/// 关闭时反向播放。语义完全不变——`barrierDismissible`、返回类型、`pageBuilder`
/// 都和原来的 `showDialog` 一一对应，确认类弹窗显式传 `false` 依然阻断。
///
/// 传 [width]（一般用 [dialogWidthOf]）会把对话框内容固定成同一宽度；
/// 不传则维持内容自适应，适合「删除确认」这类短弹窗。
Future<T?> showAppDialog<T>(
  BuildContext context, {
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color? barrierColor,
  bool useRootNavigator = true,
  double? width,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    useRootNavigator: useRootNavigator,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (ctx, _, _) {
      final child = builder(ctx);
      if (width == null) return child;
      return Center(
        child: SizedBox(width: width, child: child),
      );
    },
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
