import 'package:material_ui/material_ui.dart';

import '../../runtime/runtime_controller.dart';
import '../motion.dart';
import '../theme.dart';
import '../widgets.dart';

Color runtimeStatusColor(BuildContext context, RuntimePhase phase) =>
    switch (phase) {
      RuntimePhase.running => context.semantic.ok,
      RuntimePhase.starting || RuntimePhase.stopping => context.semantic.warn,
      RuntimePhase.error => context.semantic.danger,
      RuntimePhase.idle => Theme.of(context).colorScheme.onSurfaceVariant,
    };

/// 状态与 PID 在同一行过渡，切换状态时保留行宽。
class RuntimeStatusHeader extends StatelessWidget {
  const RuntimeStatusHeader({super.key, required this.phase, this.pid});

  final RuntimePhase phase;
  final int? pid;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final color = runtimeStatusColor(context, phase);
    final label = switch (phase) {
      RuntimePhase.idle => 'IDLE · 未运行',
      RuntimePhase.starting => 'STARTING · 启动中',
      RuntimePhase.running => 'RUNNING · 运行中',
      RuntimePhase.stopping => 'STOPPING · 停止中',
      RuntimePhase.error => 'ERROR · 出错',
    };
    return AnimatedSwitcher(
      duration: motion.fast,
      switchInCurve: motion.enter,
      switchOutCurve: motion.exit,
      layoutBuilder: (current, previous) => Stack(
        children: [
          for (final child in [...previous, ?current])
            ExcludeSemantics(
              key: child.key,
              excluding: child != current,
              child: child,
            ),
        ],
      ),
      child: Row(
        key: ValueKey(phase),
        children: [
          StatusDot(
            color: color,
            size: 7,
            pulsing: phase == RuntimePhase.running && !motion.reduceMotion,
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(11, weight: 700, color: color, letterSpacing: 0.8),
            ),
          ),
          if (pid case final int id when id > 0)
            Text('PID $id', style: mono(10.5, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

/// 流量图收放时，随高度连续移动后面的按钮，并保留图表到退场结束。
class RuntimeTrafficChart extends StatelessWidget {
  const RuntimeTrafficChart({
    super.key,
    required this.running,
    required this.values,
    this.height = 56,
    this.spacing = Insets.sm,
  });

  final bool running;
  final List<double> values;
  final double height;
  final double spacing;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: running && values.length > 1 ? 1 : 0),
      duration: motion.expand,
      curve: motion.enter,
      builder: (context, progress, child) => ClipRect(
        child: Align(
          alignment: Alignment.topCenter,
          heightFactor: progress,
          child: Opacity(opacity: progress, child: child),
        ),
      ),
      child: Padding(
        padding: EdgeInsets.only(top: spacing),
        child: Sparkline(
          values: values,
          color: context.semantic.ok,
          height: height,
        ),
      ),
    );
  }
}
