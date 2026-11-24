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

/// 点遮罩时的行为：要么关闭并带回一个结果，要么什么都不做（保持打开）。
class BarrierAction<T> {
  const BarrierAction.close(this.value) : closes = true;
  const BarrierAction.keepOpen() : value = null, closes = false;

  final T? value;
  final bool closes;
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
  Duration transitionDuration = const Duration(milliseconds: 240),
  BarrierAction<T> Function()? onBarrierTap,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: barrierColor ?? Colors.black54,
    useRootNavigator: useRootNavigator,
    transitionDuration: transitionDuration,
    pageBuilder: (ctx, _, _) {
      final child = builder(ctx);
      final sized = width == null
          ? child
          : Center(
              child: SizedBox(width: width, child: child),
            );
      if (onBarrierTap == null) return sized;
      // barrierDismissible 必须为 false，才能由我们决定「点外面做什么」：
      // 编辑规则这类弹窗点外面 = 自动保存，校验不过就不关。
      return Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                final action = onBarrierTap();
                if (action.closes) {
                  Navigator.of(ctx).pop(action.value);
                }
              },
            ),
          ),
          sized,
        ],
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
