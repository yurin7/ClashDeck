import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../runtime/runtime_controller.dart';
import 'dropdown.dart';
import 'motion.dart';
import 'overview_page.dart' show rateParts;
import 'theme.dart';
import 'widgets.dart';

enum _TrafficSpan {
  halfMinute(30, '30 秒'),
  minute(60, '1 分钟'),
  fiveMinutes(300, '5 分钟');

  const _TrafficSpan(this.seconds, this.label);
  final int seconds;
  final String label;
}

class DesktopTrafficChart extends StatefulWidget {
  const DesktopTrafficChart({
    super.key,
    required this.samples,
    required this.running,
  });

  static const historyLength = Duration(minutes: 5);
  final List<RuntimeTrafficSample> samples;
  final bool running;

  @override
  State<DesktopTrafficChart> createState() => _DesktopTrafficChartState();
}

class _DesktopTrafficChartState extends State<DesktopTrafficChart> {
  var _span = _TrafficSpan.minute;
  List<RuntimeTrafficSample>? _frozenSamples;
  RuntimeTrafficSample? _hovered;
  RuntimeTrafficSample? _pinned;
  bool _smoothTime = false;

  @override
  void didUpdateWidget(covariant DesktopTrafficChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.samples.lastOrNull?.at;
    final latest = widget.samples.lastOrNull?.at;
    if (previous != latest) {
      final elapsed = previous == null || latest == null
          ? Duration.zero
          : latest.difference(previous);
      _smoothTime =
          _frozenSamples == null &&
          elapsed > Duration.zero &&
          elapsed <= const Duration(seconds: 2);
    }
    if (!widget.running && oldWidget.running) {
      _frozenSamples = null;
      _hovered = null;
      _pinned = null;
    }
  }

  void _pauseAt(RuntimeTrafficSample selected) {
    setState(() {
      _frozenSamples ??= List.of(widget.samples);
      _pinned = selected;
    });
  }

  void _togglePause() {
    if (_frozenSamples != null) {
      setState(() {
        _frozenSamples = null;
        _pinned = null;
        _hovered = null;
      });
    } else if (widget.samples.lastOrNull case final latest?) {
      _pauseAt(_hovered ?? latest);
    }
  }

  RuntimeTrafficSample? _nearest(
    List<RuntimeTrafficSample> samples,
    DateTime end,
    double x,
    double width,
  ) {
    if (samples.isEmpty || width <= 0) return null;
    final offset = ((_span.seconds * 1000) * (1 - x / width)).round();
    final target = end.subtract(Duration(milliseconds: offset));
    if (target.isBefore(
      samples.first.at.subtract(const Duration(seconds: 1)),
    )) {
      return null;
    }
    var left = 0;
    var right = samples.length - 1;
    while (left < right) {
      final middle = (left + right) ~/ 2;
      if (samples[middle].at.isBefore(target)) {
        left = middle + 1;
      } else {
        right = middle;
      }
    }
    final next = samples[left];
    if (left == 0) return next;
    final previous = samples[left - 1];
    return next.at.difference(target).abs() <
            previous.at.difference(target).abs()
        ? next
        : previous;
  }

  void _hover(RuntimeTrafficSample? sample) {
    if (sample != _hovered) setState(() => _hovered = sample);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final download = context.semantic.ok;
    final upload = colors.primary;
    final frozen = _frozenSamples != null;
    final history = _frozenSamples ?? widget.samples;
    final end = history.lastOrNull?.at;
    final cutoff = end?.subtract(Duration(seconds: _span.seconds));
    final visible = cutoff == null
        ? const <RuntimeTrafficSample>[]
        : history.where((item) => !item.at.isBefore(cutoff)).toList();
    final marker = _hovered ?? _pinned;
    final selected = marker != null && visible.contains(marker) ? marker : null;
    final reading = selected ?? visible.lastOrNull;
    final liveMotion = !motion.reduceMotion && !frozen && selected == null;
    final timeDuration = liveMotion && _smoothTime
        ? motion.expand
        : Duration.zero;
    final peak = visible.fold(
      1024,
      (peak, sample) => math.max(peak, math.max(sample.down, sample.up)),
    );
    final upper = 1 << (peak - 1).bitLength;
    final ticks = mono(10, color: colors.onSurfaceVariant);

    return AppCard(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  '实时流量',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: display(16, weight: 650),
                ),
              ),
              AnimatedSwitcher(
                duration: motion.reduceMotion ? Duration.zero : motion.fast,
                child: frozen
                    ? Pill(
                        key: const ValueKey('paused'),
                        label: '已暂停',
                        color: colors.primary,
                        dense: true,
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(width: Insets.sm),
              SizedBox(
                width: 91,
                child: AppDropdown<_TrafficSpan>(
                  value: _span,
                  options: [
                    for (final span in _TrafficSpan.values)
                      DropdownOption(span, span.label),
                  ],
                  onChanged: (span) => setState(() {
                    _span = span;
                    _hovered = null;
                  }),
                  compact: true,
                ),
              ),
              IconButton(
                tooltip: frozen ? '恢复实时' : '暂停图表',
                onPressed: history.isEmpty ? null : _togglePause,
                icon: Icon(
                  frozen ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  size: 19,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: _TrafficRate(
                  label: '下载',
                  icon: Icons.south,
                  color: download,
                  bytes: reading?.down,
                  animate: liveMotion,
                ),
              ),
              Expanded(
                child: _TrafficRate(
                  label: '上传',
                  icon: Icons.north,
                  color: upload,
                  bytes: reading?.up,
                  animate: liveMotion,
                ),
              ),
              SizedBox(
                width: 60,
                child: Padding(
                  padding: const EdgeInsets.only(top: Insets.xs),
                  child: Text(
                    selected == null ? '' : _timeOf(selected.at),
                    textAlign: TextAlign.end,
                    style: ticks,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              SizedBox(
                width: 70,
                height: 156,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final value in [upper, upper ~/ 2, 0])
                      Text(_rateLabel(value), style: ticks, maxLines: 1),
                  ],
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 152,
                  child: LayoutBuilder(
                    builder: (context, bounds) {
                      RuntimeTrafficSample? at(double x) => end == null
                          ? null
                          : _nearest(visible, end, x, bounds.maxWidth);
                      return MouseRegion(
                        key: const ValueKey('desktop-traffic-plot'),
                        cursor: visible.isEmpty
                            ? SystemMouseCursors.basic
                            : SystemMouseCursors.precise,
                        onHover: (event) => _hover(at(event.localPosition.dx)),
                        onExit: (_) => _hover(null),
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTapUp: visible.isEmpty
                              ? null
                              : (event) {
                                  if (at(event.localPosition.dx)
                                      case final sample?) {
                                    _pauseAt(sample);
                                  }
                                },
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              TweenAnimationBuilder<double>(
                                key: ValueKey(timeDuration != Duration.zero),
                                tween: Tween(
                                  end:
                                      end?.millisecondsSinceEpoch.toDouble() ??
                                      0,
                                ),
                                duration: timeDuration,
                                curve: motion.enter,
                                builder: (context, time, _) => CustomPaint(
                                  painter: _TrafficPainter(
                                    samples: visible,
                                    end: end == null
                                        ? null
                                        : DateTime.fromMillisecondsSinceEpoch(
                                            time.round(),
                                          ),
                                    seconds: _span.seconds,
                                    upper: upper,
                                    downColor: download,
                                    upColor: upload,
                                    gridColor: colors.outlineVariant,
                                    marker: selected,
                                  ),
                                ),
                              ),
                              if (visible.isEmpty)
                                Center(
                                  child: Text(
                                    widget.running ? '正在等待流量数据…' : '启动内核后显示流量',
                                    style: hintStyle(context),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Padding(
            padding: const EdgeInsets.only(left: 70),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('${_span.label}前', style: ticks),
                Text('${_span.seconds ~/ 2} 秒前', style: ticks),
                Text(frozen && end != null ? _timeOf(end) : '现在', style: ticks),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

String _timeOf(DateTime sample) {
  final local = sample.toLocal();
  return [
    local.hour,
    local.minute,
    local.second,
  ].map((part) => part.toString().padLeft(2, '0')).join(':');
}

String _rateLabel(int bytes) {
  final rate = rateParts(bytes);
  return '${rate.value} ${rate.unit}';
}

class _TrafficRate extends StatelessWidget {
  const _TrafficRate({
    required this.label,
    required this.icon,
    required this.color,
    required this.bytes,
    required this.animate,
  });

  final String label;
  final IconData icon;
  final Color color;
  final int? bytes;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: Insets.xs),
            Text(label, style: hintStyle(context)),
          ],
        ),
        const SizedBox(height: Insets.xs),
        TweenAnimationBuilder<double>(
          key: ValueKey(animate && bytes != null),
          tween: Tween(end: bytes?.toDouble() ?? 0),
          duration: animate && bytes != null ? motion.fast : Duration.zero,
          curve: motion.enter,
          builder: (context, value, _) {
            final rate = bytes == null ? null : rateParts(value.round());
            return Wrap(
              spacing: Insets.sm,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text(
                  rate?.value ?? '—',
                  style: display(30, weight: 650, color: color).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
                if (rate != null) Text(rate.unit, style: hintStyle(context)),
              ],
            );
          },
        ),
      ],
    );
  }
}

class _TrafficPainter extends CustomPainter {
  const _TrafficPainter({
    required this.samples,
    required this.end,
    required this.seconds,
    required this.upper,
    required this.downColor,
    required this.upColor,
    required this.gridColor,
    required this.marker,
  });

  final List<RuntimeTrafficSample> samples;
  final DateTime? end;
  final int seconds;
  final int upper;
  final Color downColor;
  final Color upColor;
  final Color gridColor;
  final RuntimeTrafficSample? marker;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()..color = gridColor.withValues(alpha: 0.72);
    for (var index = 0; index <= 4; index++) {
      final y = size.height * index / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      final x = size.width * index / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    if (end == null || samples.isEmpty) return;
    canvas.save();
    canvas.clipRect(Offset.zero & size);

    double xFor(DateTime at) {
      final age = end!.difference(at).inMilliseconds;
      return (size.width - 4) * (1 - age / (seconds * 1000)) + 2;
    }

    double yFor(int value) =>
        size.height - 3 - (size.height - 6) * (value / upper).clamp(0.0, 1.0);

    if (marker case final sample?) {
      final x = xFor(sample.at);
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()..color = gridColor.withValues(alpha: 1),
      );
    }
    for (final (color, value) in [
      (downColor, (RuntimeTrafficSample sample) => sample.down),
      (upColor, (RuntimeTrafficSample sample) => sample.up),
    ]) {
      final trace = Path();
      final fill = Path();
      RuntimeTrafficSample? previous;
      for (final sample in samples) {
        final x = xFor(sample.at);
        final y = yFor(value(sample));
        if (previous == null ||
            sample.at.difference(previous.at).inSeconds >= 4) {
          if (previous != null) {
            fill.lineTo(xFor(previous.at), size.height);
            fill.close();
          }
          trace.moveTo(x, y);
          fill.moveTo(x, size.height);
          fill.lineTo(x, y);
        } else {
          trace.lineTo(x, y);
          fill.lineTo(x, y);
        }
        previous = sample;
      }
      fill.lineTo(xFor(samples.last.at), size.height);
      fill.close();
      canvas.drawPath(
        fill,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              color.withValues(alpha: 0.19),
              color.withValues(alpha: 0.015),
            ],
          ).createShader(Offset.zero & size),
      );
      canvas.drawPath(
        trace,
        Paint()
          ..color = color
          ..strokeWidth = 1.75
          ..strokeJoin = StrokeJoin.round
          ..style = PaintingStyle.stroke,
      );
      final point = marker ?? samples.last;
      canvas.drawCircle(
        Offset(xFor(point.at), yFor(value(point))),
        marker == null ? 2 : 3.5,
        Paint()..color = color,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter oldDelegate) =>
      samples != oldDelegate.samples ||
      end != oldDelegate.end ||
      seconds != oldDelegate.seconds ||
      upper != oldDelegate.upper ||
      downColor != oldDelegate.downColor ||
      upColor != oldDelegate.upColor ||
      gridColor != oldDelegate.gridColor ||
      marker != oldDelegate.marker;
}
