import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';

/// 内核启停按钮：停止 / 运行中 / 处理中三种状态之间交叉淡入淡出。
///
/// 只重建按钮自身；动画时长走 [Motion]，系统开启「减少动画」时自动降为短促切换。
///
/// 三种状态必须严格同宽同高：启动态是铺满的 [AccentButton]，停止/处理中是
/// [OutlinedButton]，所以两处都要显式给 `minimumSize` 并让 AnimatedSwitcher
/// 的 Stack 以 `StackFit.expand` 约束子级，否则 OutlinedButton 会按内容收缩，
/// 出现「停止按钮比启动按钮短」的问题（0.3.0 实测）。
class StartStopButton extends StatelessWidget {
  const StartStopButton({
    super.key,
    required this.running,
    required this.busy,
    required this.onStart,
    required this.onStop,
    this.busySpinner = false,
    this.busyLabel = '启动中…',
  });

  final bool running;
  final bool busy;
  final VoidCallback onStart;
  final VoidCallback onStop;

  /// 处理中是否显示转圈（概览页）；false 时显示禁用按钮（运行页）。
  final bool busySpinner;
  final String busyLabel;

  /// 与 [AccentButton] 的 46 高、24 横向内边距、14 圆角保持一致。
  static ButtonStyle get _outlinedStyle => OutlinedButton.styleFrom(
    minimumSize: const Size.fromHeight(46),
    padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(Radiuses.md)),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    final Widget child;
    if (busy) {
      child = busySpinner
          ? const Center(
              key: ValueKey('start-stop-busy'),
              child: SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          : OutlinedButton.icon(
              key: const ValueKey('start-stop-busy'),
              style: _outlinedStyle,
              onPressed: null,
              icon: const Icon(Icons.play_arrow_rounded, size: 20),
              label: Text(busyLabel),
            );
    } else if (running) {
      child = OutlinedButton.icon(
        key: const ValueKey('start-stop-stop'),
        style: _outlinedStyle,
        onPressed: onStop,
        icon: const Icon(Icons.stop_circle_outlined, size: 20),
        label: const Text('停止内核'),
      );
    } else {
      child = AccentButton(
        key: const ValueKey('start-stop-start'),
        label: '启动内核',
        icon: Icons.play_arrow_rounded,
        expand: true,
        onPressed: onStart,
      );
    }
    return SizedBox(
      width: double.infinity,
      height: 46,
      child: AnimatedSwitcher(
        duration: motion.expand,
        switchInCurve: motion.enter,
        switchOutCurve: motion.exit,
        layoutBuilder: (current, previous) => Stack(
          fit: StackFit.expand,
          alignment: Alignment.center,
          children: [...previous, ?current],
        ),
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: child,
      ),
    );
  }
}
