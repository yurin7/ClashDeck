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
/// `MediaQuery.disableAnimations`（系统「减少动画」）时使用 [calm]。
/// 链内让位和落位直接切换状态，其余组件过渡保留 60ms。
class Motion {
  const Motion({
    required this.fast,
    required this.chip,
    required this.arrow,
    required this.expand,
    required this.page,
    required this.snapBack,
    required this.relayPreview,
    required this.relayReorder,
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

  /// 拖拽被拒绝后的「滑回原位」回弹。
  final Duration snapBack;

  /// 链节拖过相邻胶囊时的换位预览。
  final Duration relayPreview;

  /// 链式成员顺序改变后的过渡。
  final Duration relayReorder;

  /// 当前是否处于「减少动画」。
  final bool reduceMotion;

  static const Motion normal = Motion(
    fast: Duration(milliseconds: 140),
    chip: Duration(milliseconds: 140),
    arrow: Duration(milliseconds: 180),
    expand: Duration(milliseconds: 220),
    page: Duration(milliseconds: 300),
    snapBack: Duration(milliseconds: 240),
    relayPreview: Duration(milliseconds: 120),
    relayReorder: Duration(milliseconds: 200),
    reduceMotion: false,
  );

  /// 减少动画时的过渡时长。
  static const Motion calm = Motion(
    fast: Duration(milliseconds: 60),
    chip: Duration(milliseconds: 60),
    arrow: Duration(milliseconds: 60),
    expand: Duration(milliseconds: 60),
    page: Duration(milliseconds: 60),
    snapBack: Duration(milliseconds: 60),
    relayPreview: Duration.zero,
    relayReorder: Duration.zero,
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

/// 内容增减时平滑调整区块尺寸，后续内容随之移动。
class MotionSize extends StatelessWidget {
  const MotionSize({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return AnimatedSize(
      duration: motion.expand,
      curve: motion.enter,
      alignment: Alignment.topLeft,
      child: child,
    );
  }
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

/// 循环状态灯（启动中呼吸）用的周期，独立于转场时长上限。
const Duration kStatusPulseDuration = Duration(milliseconds: 1600);

/// Pulse 顶部小猫的浮动周期（往返一次），同样不属于转场时长。
const Duration kMascotFloatDuration = Duration(milliseconds: 3200);

/// Pulse 叠加层滑入/退出：比页面转场稍长，让下层主界面保持可见。
const Duration kPulseEnterDuration = Duration(milliseconds: 360);
const Duration kPulseExitDuration = Duration(milliseconds: 260);

/// Pulse 背景层循环周期（mesh 漂移 + 粒子）。
const Duration kPulseBackdropPeriod = Duration(seconds: 24);

/// Pulse 内容卡片入场总时长（每张再按 40ms 阶梯错开）。
const Duration kPulseContentEnterDuration = Duration(milliseconds: 600);

/// Pulse 测速雷达的循环周期（脉冲环 / 呼吸光晕 / 底图扫掠）。
const Duration kPulseRadarPeriod = Duration(milliseconds: 2400);

/// 测速结果行的条形与数字动画时长。
const Duration kLatencyBarDuration = Duration(milliseconds: 300);
const Duration kLatencyCountDuration = Duration(milliseconds: 200);

/// 失败行的一次性抖动时长。
const Duration kLatencyShakeDuration = Duration(milliseconds: 120);

/// 第一名结果行的一次性扫光时长。
const Duration kSheenDuration = Duration(milliseconds: 200);
