import 'package:material_ui/material_ui.dart';

import '../runtime/windows_connections.dart';
import 'motion.dart';
import 'overview_page.dart' show rateParts;
import 'theme.dart';
import 'widgets.dart';
import 'widgets/app_ink.dart';

class DesktopActivity extends StatelessWidget {
  const DesktopActivity({
    super.key,
    required this.monitor,
    required this.visible,
    required this.onOpenConnections,
    required this.onInspectProcess,
  });

  final WindowsConnectionMonitor monitor;
  final bool visible;
  final VoidCallback onOpenConnections;
  final ValueChanged<String> onInspectProcess;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: monitor,
      builder: (context, _) {
        final traffic = <String, _ProcessTraffic>{};
        for (final entry in monitor.history.open) {
          traffic
              .putIfAbsent(
                entry.processKey,
                () => _ProcessTraffic(
                  entry.processKey,
                  entry.process.isEmpty ? '未识别进程' : entry.process,
                ),
              )
              .include(entry);
        }
        final ranked = traffic.values.toList()
          ..sort((a, b) {
            final byRate = b.rate.compareTo(a.rate);
            if (byRate != 0) return byRate;
            final byConnections = b.connections.compareTo(a.connections);
            return byConnections != 0
                ? byConnections
                : a.name.compareTo(b.name);
          });
        final peak = ranked.firstOrNull?.rate ?? 0;
        final colors = Theme.of(context).colorScheme;
        return AppCard(
          padding: const EdgeInsets.all(Insets.lg),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 254),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text('流量排行', style: display(16, weight: 650)),
                    ),
                    IconButton(
                      tooltip: '打开连接页',
                      onPressed: onOpenConnections,
                      icon: const Icon(Icons.arrow_outward_rounded, size: 17),
                    ),
                  ],
                ),
                if (ranked.isEmpty)
                  SizedBox(
                    height: 200,
                    child: Center(
                      child: EmptyHint(
                        compact: true,
                        icon: Icons.monitor_heart_outlined,
                        title: monitor.running ? '暂无活动连接' : '暂无进程流量',
                        message: monitor.running ? null : '启动内核后按进程统计流量',
                      ),
                    ),
                  )
                else ...[
                  for (final entry in ranked.take(3))
                    _ProcessRow(
                      key: ValueKey(entry.key),
                      entry: entry,
                      fraction: peak == 0 ? 0 : entry.rate / peak,
                      onTap: () => onInspectProcess(entry.key),
                    ),
                  if (monitor.stale)
                    Padding(
                      padding: const EdgeInsets.only(top: Insets.xs),
                      child: Text(
                        '连接采样暂未更新',
                        style: hintStyle(context)
                            ?.copyWith(color: colors.error),
                      ),
                    ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ProcessTraffic {
  _ProcessTraffic(this.key, this.name);

  final String key;
  final String name;
  int rate = 0;
  int connections = 0;
  bool sampled = false;

  void include(WindowsConnection entry) {
    rate += (entry.downRate ?? 0) + (entry.upRate ?? 0);
    sampled = sampled || entry.downRate != null || entry.upRate != null;
    connections++;
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    super.key,
    required this.entry,
    required this.fraction,
    required this.onTap,
  });

  final _ProcessTraffic entry;
  final double fraction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final rate = rateParts(entry.rate);
    final radius = BorderRadius.circular(Radiuses.sm);
    return Padding(
      padding: const EdgeInsets.only(top: Insets.xs),
      child: Material(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.55),
        borderRadius: radius,
        clipBehavior: Clip.antiAlias,
        child: AppInkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.all(Insets.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.name,
                        style: display(13, weight: 580),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: Insets.xs),
                    Text(
                      entry.sampled ? '${rate.value} ${rate.unit}' : '—',
                      style: mono(10, color: colors.primary),
                    ),
                    const Icon(Icons.chevron_right, size: 15),
                  ],
                ),
                Text('${entry.connections} 条连接', style: hintStyle(context)),
                const SizedBox(height: Insets.sm),
                ClipRRect(
                  borderRadius: BorderRadius.circular(2),
                  child: ColoredBox(
                    color: colors.outlineVariant,
                    child: SizedBox(
                      height: 3,
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: TweenAnimationBuilder<double>(
                          tween: Tween(begin: 0, end: fraction),
                          duration: motion.reduceMotion
                              ? Duration.zero
                              : motion.fast,
                          curve: motion.enter,
                          builder: (context, value, child) =>
                              FractionallySizedBox(
                                widthFactor: value,
                                heightFactor: 1,
                                child: child,
                              ),
                          child: DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [colors.primary, context.semantic.ok],
                              ),
                            ),
                          ),
                        ),
                      ),
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
