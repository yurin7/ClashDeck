import 'package:material_ui/material_ui.dart';

/// 全站动效 token。
///
/// 只允许用这里的时长/曲线，页面里不再散写 `Duration(milliseconds: …)`
/// 或 `Curves.…`。数值来自 DESIGN_SYSTEM「动效」一节：
///
/// - 微交互（按压、chip 选中）120–150ms
/// - 容器/展开 200–240ms
/// - 页面 300ms（`appRoute` 自带，这里只做参考值）
/// - 禁止 > 350ms
///
/// `MediaQuery.disableAnimations`（系统「减少动画」）时降为 60ms，
/// 不做大幅位移，只保留最低限度的状态变化提示。
class Motion {
  const Motion({
    required this.fast,
    required this.chip,
    required this.arrow,
    required this.expand,
    required this.page,
    required this.reduceMotion,
  });

  /// 微交互：按压返回、按钮 cross-fade。
  final Duration fast;

  /// chip 选中：背景/描边与 0.98→1 的缩放。
  final Duration chip;

  /// 折叠箭头旋转。
  final Duration arrow;

  /// 容器/区块展开收起。
  final Duration expand;

  /// 页面转场（仅记录，实际由 `appRoute` 使用）。
  final Duration page;

  /// 当前是否处于「减少动画」。
  final bool reduceMotion;

  static const Motion normal = Motion(
    fast: Duration(milliseconds: 140),
    chip: Duration(milliseconds: 140),
    arrow: Duration(milliseconds: 180),
    expand: Duration(milliseconds: 220),
    page: Duration(milliseconds: 300),
    reduceMotion: false,
  );

  /// 减少动画：保留 60ms 的淡入淡出，不跳变也不拖沓。
  static const Motion calm = Motion(
    fast: Duration(milliseconds: 60),
    chip: Duration(milliseconds: 60),
    arrow: Duration(milliseconds: 60),
    expand: Duration(milliseconds: 60),
    page: Duration(milliseconds: 60),
    reduceMotion: true,
  );

  static Motion of(BuildContext context) {
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return reduce ? calm : normal;
  }

  /// 进场曲线：减速收尾。
  Curve get enter => Curves.easeOutCubic;

  /// 退场曲线：加速离开。
  Curve get exit => Curves.easeInCubic;
}

/// 单项进场：fade + 0.98→1 缩放。
///
/// 只包变化的那一项（新加的成员 chip、新插入的行），**不要**包整张列表，
/// 否则就是「整列表 fade 入场」，明确禁止。首次挂载时播放一次，之后
/// 由父级 key 决定是否重播。
class MotionEntrance extends StatelessWidget {
  const MotionEntrance({super.key, required this.child, this.duration});

  final Widget child;
  final Duration? duration;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween<double>(begin: 0, end: 1),
      duration: duration ?? motion.chip,
      curve: motion.enter,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
      ),
      child: child,
    );
  }
}
