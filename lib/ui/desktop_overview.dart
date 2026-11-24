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
import '../runtime/windows_connections.dart';
import 'desktop_activity.dart';
import 'desktop_hover.dart';
import 'desktop_traffic.dart';
import 'dropdown.dart';
import 'motion.dart';
import 'pulse_page.dart';
import 'theme.dart';
import 'widgets.dart';
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
    required this.connections,
    required this.tunStack,
    required this.admin,
    required this.onTunStack,
    required this.onStart,
    required this.onShowLogs,
    required this.onOpenConnections,
    required this.onInspectProcess,
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
  final WindowsConnectionMonitor connections;
  final String? tunStack;
  final bool admin;
  final ValueChanged<String?> onTunStack;
  final VoidCallback onStart;
  final VoidCallback onShowLogs;
  final VoidCallback onOpenConnections;
  final ValueChanged<String> onInspectProcess;
  final VoidCallback onOpenProfiles;
  final VoidCallback onEditProfile;

  @override
  State<DesktopOverview> createState() => _DesktopOverviewState();
}

class _DesktopOverviewState extends State<DesktopOverview> {
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
        if (_samples.lastOrNull?.at.isAfter(sample.at) ?? false) {
          _samples.clear();
        }
        final cutoff = sample.at.subtract(DesktopTrafficChart.historyLength);
        _samples.removeWhere((item) => item.at.isBefore(cutoff));
        _samples.add(sample);
      }
    }
    if (widget.visible) setState(() {});
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

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final status = runtimeStatusColor(context, _runtime.phase);
    final blocked = _testing || widget.busy || _runtime.restarting;
    final running = _runtime.phase == RuntimePhase.running;
    final startingOrStopping = _runtime.isBusy;
    final needsAdmin = widget.tunStack != null && !widget.admin && !running;
    final active = widget.active;
    final prefs = widget.prefs;
    final error = _runtime.lastError;
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
                        child: AnimatedSwitcher(
                          duration: motion.reduceMotion
                              ? Duration.zero
                              : motion.fast,
                          switchInCurve: motion.enter,
                          child: Pill(
                            key: ValueKey(_runtime.phase),
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
                      ),
                    ],
                  ),
                ),
                DesktopHover(
                  borderRadius: BorderRadius.circular(Radiuses.xl),
                  child: IconButton(
                    onPressed: widget.onShowLogs,
                    tooltip: '内核日志',
                    icon: const Icon(Icons.terminal_outlined, size: 20),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                SizedBox(
                  width: 148,
                  child: DesktopHover(
                    enabled: active != null && !blocked && !startingOrStopping,
                    borderRadius: BorderRadius.circular(Radiuses.md),
                    color: running ? context.semantic.ok : Colors.white,
                    intensity: running ? 1 : 1.8,
                    lift: 2,
                    tilt: 0.05,
                    child: active == null || blocked
                        ? OutlinedButton(
                            onPressed: null,
                            child: Text(_testing ? '测速中…' : '启动内核'),
                          )
                        : needsAdmin
                        ? FilledButton.icon(
                            onPressed: widget.onStart,
                            icon: const Icon(
                              Icons.admin_panel_settings_outlined,
                              size: 17,
                            ),
                            label: const Text('授权 TUN'),
                          )
                        : StartStopButton(
                            phase: _runtime.phase,
                            onStart: widget.onStart,
                            onStop: _runtime.stop,
                          ),
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
            MotionSize(
              child: error == null
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(top: Insets.sm),
                      child: Text(error, style: TextStyle(color: scheme.error)),
                    ),
            ),
            const SizedBox(height: Insets.lg),
            _OverviewColumns(
              alignHeight: true,
              primary: DesktopTrafficChart(
                samples: List.of(_samples),
                running: running,
              ),
              secondary: DesktopActivity(
                monitor: widget.connections,
                visible: widget.visible,
                onOpenConnections: widget.onOpenConnections,
                onInspectProcess: widget.onInspectProcess,
              ),
            ),
            if (prefs != null) ...[
              const SizedBox(height: Insets.md),
              PulsePage(
                appVersion: widget.appVersion,
                profileName: active?.name ?? '—',
                profile: widget.profile,
                prefs: prefs,
                runtime: _runtime,
                connectionCount: () async => widget.connections.count,
                speedTest: _speedTest,
                desktopLayout: (speed, updates, runtime) => _OverviewColumns(
                  primary: runtime,
                  secondary: Column(
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
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _OverviewColumns extends StatelessWidget {
  const _OverviewColumns({
    required this.primary,
    required this.secondary,
    this.alignHeight = false,
  });

  final Widget primary;
  final Widget secondary;
  final bool alignHeight;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, bounds) => bounds.maxWidth >= 850
        ? Table(
            columnWidths: const {
              0: FlexColumnWidth(),
              1: FixedColumnWidth(Insets.lg),
              2: FixedColumnWidth(322),
            },
            children: [
              TableRow(
                children: [
                  primary,
                  const SizedBox.shrink(),
                  if (alignHeight)
                    TableCell(
                      verticalAlignment: TableCellVerticalAlignment.fill,
                      child: secondary,
                    )
                  else
                    secondary,
                ],
              ),
            ],
          )
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: Insets.md),
              secondary,
            ],
          ),
  );
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
              DesktopHover(
                enabled: onSwitch != null,
                borderRadius: BorderRadius.circular(Radiuses.md),
                lift: 1,
                child: OutlinedButton.icon(
                  onPressed: onSwitch,
                  icon: const Icon(Icons.swap_horiz, size: 16),
                  label: const Text('切换配置'),
                ),
              ),
              const SizedBox(width: Insets.xs),
              DesktopHover(
                enabled: onEdit != null,
                borderRadius: BorderRadius.circular(Radiuses.xl),
                child: IconButton(
                  onPressed: onEdit,
                  tooltip: '编辑已选配置',
                  icon: const Icon(Icons.edit_outlined, size: 17),
                ),
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
