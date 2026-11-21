import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/model/profile.dart';
import '../core/update/update_check.dart';
import '../data/app_prefs.dart';
import '../data/profile_store.dart';
import '../runtime/runtime_config.dart';
import '../runtime/runtime_controller.dart';
import '../runtime/speed_test.dart';
import 'dropdown.dart';
import 'motion.dart';
import 'overview_page.dart' show rateParts;
import 'pulse_page.dart';
import 'startup_issues_dialog.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/edit_dialog.dart';
import 'widgets/profile_icon.dart';
import 'widgets/runtime_status.dart';
import 'widgets/start_stop_button.dart';

class DesktopOverview extends StatefulWidget {
  const DesktopOverview({
    super.key,
    required this.runtime,
    required this.active,
    required this.origin,
    required this.profile,
    required this.prefs,
    required this.appVersion,
    required this.busy,
    required this.visible,
    required this.connectionCount,
    required this.tunStack,
    required this.admin,
    required this.onTunStack,
    required this.onRequestElevation,
    required this.onOpenProfiles,
    required this.onEditProfile,
  });

  final RuntimeController runtime;
  final StoredProfile? active;
  final ProfileOrigin origin;
  final Profile profile;
  final AppPrefs? prefs;
  final String appVersion;
  final bool busy;
  final bool visible;
  final Future<int?> Function() connectionCount;
  final String? tunStack;
  final bool admin;
  final ValueChanged<String?> onTunStack;
  final VoidCallback onRequestElevation;
  final VoidCallback onOpenProfiles;
  final VoidCallback onEditProfile;

  @override
  State<DesktopOverview> createState() => _DesktopOverviewState();
}

class _DesktopOverviewState extends State<DesktopOverview> {
  static const _window = Duration(seconds: 60);
  final _samples = <RuntimeTrafficSample>[];
  bool _testing = false;

  RuntimeController get _runtime => widget.runtime;

  @override
  void initState() {
    super.initState();
    _runtime.addListener(_onRuntimeChanged);
  }

  @override
  void dispose() {
    _runtime.removeListener(_onRuntimeChanged);
    super.dispose();
  }

  void _onRuntimeChanged() {
    final phase = _runtime.phase;
    if (phase != RuntimePhase.running) {
      _samples.clear();
    } else if (_runtime.latestTraffic case final sample?) {
      if (_samples.lastOrNull != sample) {
        final cutoff = sample.at.subtract(_window);
        _samples.removeWhere((item) => item.at.isBefore(cutoff));
        _samples.add(sample);
      }
    }
    if (widget.visible) setState(() {});
  }

  Future<void> _start() async {
    if (await _runtime.start() || !mounted) return;
    final report = _runtime.startupReport;
    if (report != null && await showStartupIssuesDialog(context, report)) {
      if (mounted) await _runtime.start(force: true);
    }
  }

  Future<SpeedTestResult> _speedTest(
    String node, {
    SpeedSourceChoice source = SpeedSourceChoice.defaultChoice,
    SpeedTestCancelToken? cancelToken,
    void Function(SpeedTestProgress progress)? onProgress,
    void Function(SpeedTestStage stage)? onStage,
  }) async {
    if (_testing || _runtime.isBusy || widget.busy) {
      return SpeedTestResult.failed('内核正在切换，请稍后测速');
    }
    setState(() => _testing = true);
    try {
      return await _runtime.runSpeedTest(
        node,
        source: source,
        cancelToken: cancelToken,
        onProgress: onProgress,
        onStage: onStage,
      );
    } finally {
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _showLogs() async {
    final logs = await _runtime.loadLogs();
    if (!mounted) return;
    await showAppDialog<void>(
      context,
      width: math.min(720, MediaQuery.sizeOf(context).width - 48),
      builder: (ctx) => EditDialog(
        title: '内核日志',
        confirmLabel: '关闭',
        onConfirm: () => Navigator.pop(ctx),
        content: SizedBox(
          height: 320,
          child: SingleChildScrollView(
            child: SelectableText(
              logs.isEmpty ? '暂无内核日志' : logs.join('\n'),
              style: monoStyle(ctx, size: 11),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final status = runtimeStatusColor(context, _runtime.phase);
    final blocked = _testing || widget.busy || _runtime.restarting;
    final running = _runtime.phase == RuntimePhase.running;
    final startingOrStopping = _runtime.isBusy;
    final needsAdmin = widget.tunStack != null && !widget.admin && !running;
    final active = widget.active;
    final prefs = widget.prefs;
    final traffic = _TrafficCard(
      samples: List.of(_samples),
      latest: _runtime.latestTraffic,
      running: _runtime.phase == RuntimePhase.running,
    );
    return Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1420),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(24, 11, 24, 24),
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text('概览', style: display(27, weight: 670)),
                      const SizedBox(width: Insets.md),
                      Flexible(
                        child: Pill(
                          label: switch (_runtime.phase) {
                            RuntimePhase.idle => '未运行',
                            RuntimePhase.starting => '启动中',
                            RuntimePhase.running => '运行中',
                            RuntimePhase.stopping => '停止中',
                            RuntimePhase.error => '运行错误',
                          },
                          color: status,
                          dense: true,
                        ),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: _showLogs,
                  tooltip: '内核日志',
                  icon: const Icon(Icons.terminal_outlined, size: 20),
                ),
                const SizedBox(width: Insets.sm),
                SizedBox(
                  width: 148,
                  child: active == null || blocked
                      ? OutlinedButton(
                          onPressed: null,
                          child: Text(_testing ? '测速中…' : '启动内核'),
                        )
                      : needsAdmin
                      ? FilledButton.icon(
                          onPressed: widget.onRequestElevation,
                          icon: const Icon(
                            Icons.admin_panel_settings_outlined,
                            size: 17,
                          ),
                          label: const Text('授权 TUN'),
                        )
                      : StartStopButton(
                          phase: _runtime.phase,
                          onStart: _start,
                          onStop: _runtime.stop,
                        ),
                ),
              ],
            ),
            const SizedBox(height: Insets.md),
            if (active != null)
              _ActiveProfileCard(
                profile: active,
                origin: widget.origin,
                running: running && !_testing,
                testing: _testing,
                port: _runtime.proxyPort,
                stack: widget.tunStack,
                needsAdmin: needsAdmin,
                onSwitch: widget.busy ? null : widget.onOpenProfiles,
                onEdit: widget.busy ? null : widget.onEditProfile,
                onStack: blocked || running || startingOrStopping
                    ? null
                    : widget.onTunStack,
              )
            else
              Text('从配置库新建或导入配置后即可启动内核。', style: hintStyle(context)),
            if (_runtime.lastError case final error?)
              Padding(
                padding: const EdgeInsets.only(top: Insets.sm),
                child: Text(error, style: TextStyle(color: scheme.error)),
              ),
            const SizedBox(height: Insets.lg),
            if (prefs == null)
              traffic
            else
              PulsePage(
                appVersion: widget.appVersion,
                profileName: active?.name ?? '—',
                profile: widget.profile,
                prefs: prefs,
                runtime: _runtime,
                connectionCount: widget.connectionCount,
                speedTest: _speedTest,
                desktopLayout: (speed, updates, runtime) => LayoutBuilder(
                  builder: (context, bounds) {
                    final tools = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        speed,
                        const SizedBox(height: Insets.md),
                        updates,
                        Align(
                          alignment: Alignment.centerRight,
                          child: TextButton.icon(
                            onPressed: () =>
                                launchUrl(Uri.parse(clashDeckProjectUrl)),
                            icon: const Icon(Icons.open_in_new, size: 15),
                            label: const Text('项目主页'),
                          ),
                        ),
                      ],
                    );
                    final main = Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        traffic,
                        const SizedBox(height: Insets.md),
                        runtime,
                      ],
                    );
                    return bounds.maxWidth >= 850
                        ? Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(child: main),
                              const SizedBox(width: Insets.lg),
                              SizedBox(width: 322, child: tools),
                            ],
                          )
                        : Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              main,
                              const SizedBox(height: Insets.md),
                              tools,
                            ],
                          );
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ActiveProfileCard extends StatelessWidget {
  const _ActiveProfileCard({
    required this.profile,
    required this.origin,
    required this.running,
    required this.testing,
    required this.port,
    required this.stack,
    required this.needsAdmin,
    this.onSwitch,
    this.onEdit,
    this.onStack,
  });

  final StoredProfile profile;
  final ProfileOrigin origin;
  final bool running;
  final bool testing;
  final int port;
  final String? stack;
  final bool needsAdmin;
  final VoidCallback? onSwitch;
  final VoidCallback? onEdit;
  final ValueChanged<String?>? onStack;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = colors.primary;
    return AppCard(
      accent: accent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              ProfileIcon(
                origin: origin,
                selected: true,
                running: running,
                size: 42,
              ),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      testing
                          ? '测速前选用的配置'
                          : running
                          ? '运行中'
                          : '当前选用',
                      style: hintStyle(context)?.copyWith(color: accent),
                    ),
                    const SizedBox(height: Insets.xs),
                    AnimatedSwitcher(
                      duration: Motion.of(context).fast,
                      layoutBuilder: (current, previous) => Stack(
                        alignment: Alignment.centerLeft,
                        children: [...previous, ?current],
                      ),
                      child: Text(
                        key: ValueKey(profile.fileName),
                        profile.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: display(19, weight: 670),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: Insets.md),
              OutlinedButton.icon(
                onPressed: onSwitch,
                icon: const Icon(Icons.swap_horiz, size: 16),
                label: const Text('切换配置'),
              ),
              const SizedBox(width: Insets.xs),
              IconButton(
                onPressed: onEdit,
                tooltip: '编辑已选配置',
                icon: const Icon(Icons.edit_outlined, size: 17),
              ),
            ],
          ),
          const SizedBox(height: Insets.md),
          const Hairline(),
          const SizedBox(height: Insets.sm),
          Wrap(
            spacing: Insets.md,
            runSpacing: Insets.xs,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              Text('接管方式', style: hintStyle(context)),
              SizedBox(
                width: 145,
                child: AppDropdown<String?>(
                  compact: true,
                  expand: true,
                  value: stack,
                  onChanged: (value) => onStack?.call(value),
                  enabled: onStack != null,
                  options: const [
                    DropdownOption(null, '本地代理端口'),
                    DropdownOption(
                      RuntimeConfig.defaultWindowsStack,
                      'TUN · Mixed',
                    ),
                    DropdownOption('system', 'TUN · System'),
                    DropdownOption('gvisor', 'TUN · gVisor'),
                  ],
                ),
              ),
              _ProxyEndpoint(port: port),
              if (needsAdmin)
                Text('授权后会以管理员身份重新打开应用', style: hintStyle(context)),
            ],
          ),
        ],
      ),
    );
  }
}

class _ProxyEndpoint extends StatelessWidget {
  const _ProxyEndpoint({required this.port});

  final int port;

  @override
  Widget build(BuildContext context) {
    final address = '127.0.0.1:$port';
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(address, style: monoStyle(context, size: 11.5)),
        IconButton(
          tooltip: '复制本地代理地址',
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: address));
            if (context.mounted) showToast(context, '已复制代理地址');
          },
          icon: const Icon(Icons.content_copy, size: 15),
        ),
      ],
    );
  }
}

class _TrafficCard extends StatelessWidget {
  const _TrafficCard({
    required this.samples,
    required this.latest,
    required this.running,
  });

  final List<RuntimeTrafficSample> samples;
  final RuntimeTrafficSample? latest;
  final bool running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final download = context.semantic.ok;
    final upload = scheme.primary;
    final peak = samples.fold(
      1024,
      (peak, item) => math.max(peak, math.max(item.down, item.up)),
    );
    final top = math.pow(2, (math.log(peak) / math.ln2).ceil()).toInt();
    final tickStyle = mono(10, color: scheme.onSurfaceVariant);
    return AppCard(
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('实时流量', style: display(16, weight: 650))),
              Text('最近 60 秒', style: hintStyle(context)),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              Expanded(
                child: _TrafficRate(
                  label: '下载',
                  icon: Icons.south,
                  color: download,
                  bytes: latest?.down,
                ),
              ),
              Expanded(
                child: _TrafficRate(
                  label: '上传',
                  icon: Icons.north,
                  color: upload,
                  bytes: latest?.up,
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              SizedBox(
                width: 62,
                height: 150,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final value in [top, top ~/ 2, 0])
                      Text(_rateLabel(value), style: tickStyle, maxLines: 1),
                  ],
                ),
              ),
              Expanded(
                child: SizedBox(
                  height: 144,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CustomPaint(
                        painter: _TrafficPainter(
                          samples: samples,
                          maxRate: top,
                          downColor: download,
                          upColor: upload,
                          gridColor: scheme.outlineVariant.withValues(
                            alpha: 0.8,
                          ),
                        ),
                      ),
                      if (samples.isEmpty)
                        Center(
                          child: Text(
                            running ? '正在等待流量数据…' : '启动内核后显示本地代理流量',
                            style: hintStyle(context),
                            textAlign: TextAlign.center,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Padding(
            padding: const EdgeInsets.only(left: 62),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('60 秒前', style: tickStyle),
                Text('30 秒前', style: tickStyle),
                Text('现在', style: tickStyle),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
  });

  final String label;
  final IconData icon;
  final Color color;
  final int? bytes;

  @override
  Widget build(BuildContext context) {
    final rate = bytes == null ? null : rateParts(bytes!);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Icon(icon, size: 15, color: color),
            const SizedBox(width: 6),
            Text(label, style: hintStyle(context)),
          ],
        ),
        const SizedBox(height: 4),
        Wrap(
          spacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              rate?.value ?? '—',
              style: display(29, weight: 650, color: color),
            ),
            if (rate != null) Text(rate.unit, style: hintStyle(context)),
          ],
        ),
      ],
    );
  }
}

class _TrafficPainter extends CustomPainter {
  const _TrafficPainter({
    required this.samples,
    required this.maxRate,
    required this.downColor,
    required this.upColor,
    required this.gridColor,
  });

  final List<RuntimeTrafficSample> samples;
  final int maxRate;
  final Color downColor;
  final Color upColor;
  final Color gridColor;

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = gridColor
      ..strokeWidth = 1;
    for (var i = 0; i <= 4; i++) {
      final y = size.height * i / 4;
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
      final x = size.width * i / 4;
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    if (samples.isEmpty) return;
    final end = samples.last.at;
    for (final (color, reading) in [
      (downColor, (RuntimeTrafficSample item) => item.down),
      (upColor, (RuntimeTrafficSample item) => item.up),
    ]) {
      final pen = Paint()
        ..color = color
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke;
      final path = Path();
      DateTime? previous;
      Offset? last;
      for (final sample in samples) {
        final seconds = end.difference(sample.at).inMilliseconds / 1000;
        final x = size.width * (1 - seconds / 60).clamp(0.0, 1.0);
        final y =
            size.height -
            2 -
            (size.height - 4) * (reading(sample) / maxRate).clamp(0.0, 1.0);
        if (previous == null || sample.at.difference(previous).inSeconds >= 4) {
          path.moveTo(x, y);
        } else {
          path.lineTo(x, y);
        }
        previous = sample.at;
        last = Offset(x, y);
      }
      canvas.drawPath(path, pen);
      if (last != null) {
        canvas.drawCircle(last.translate(-2, 0), 2.3, Paint()..color = color);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _TrafficPainter oldDelegate) =>
      samples != oldDelegate.samples ||
      maxRate != oldDelegate.maxRate ||
      downColor != oldDelegate.downColor ||
      upColor != oldDelegate.upColor ||
      gridColor != oldDelegate.gridColor;
}
