import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/model/profile.dart';
import '../core/update/update_check.dart';
import '../data/app_prefs.dart';
import '../runtime/runtime_controller.dart';
import '../runtime/speed_test.dart';
import 'motion.dart';
import 'pulse_time.dart';
import 'chips.dart';
import 'fields.dart';
import 'theme.dart';
import 'update_dialog.dart';
import 'widgets.dart';
import 'widgets/app_ink.dart';
import 'widgets/delay_badge.dart';

/// 批量测速的注入点（测试用假实现替换真实内核请求）。
typedef PulseMeasure = Future<Map<String, int?>> Function(
  List<String> names, {
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
});

/// 负一屏 Pulse：概览左滑进来的一页，放「状态、测速、更新、运行信息」。
///
/// 刻意不放快捷开关（启动/停止/模式切换仍在概览页），这里只读 + 测速。
typedef PulseSpeedTest = Future<SpeedTestResult> Function(
  String node, {
  SpeedSourceChoice source,
  void Function(SpeedTestProgress progress)? onProgress,
  void Function(SpeedTestStage stage)? onStage,
  SpeedTestCancelToken? cancelToken,
});

class PulsePage extends StatefulWidget {
  const PulsePage({
    super.key,
    required this.appVersion,
    required this.profileName,
    required this.profile,
    required this.prefs,
    this.runtime,
    this.measure,
    this.connectionCount,
    this.checkUpdate,
    this.openUrl,
    this.startKernel,
    this.globalExit,
    this.onLatencyCached,
    this.speedTest,
    this.onClose,
    this.desktopLayout,
  });

  final String appVersion;
  final String profileName;
  final Profile profile;
  final AppPrefs prefs;
  final RuntimeController? runtime;
  final PulseMeasure? measure;

  /// 下载测速（Pulse 测速卡用）。
  final PulseSpeedTest? speedTest;
  final Future<int?> Function()? connectionCount;
  final Future<UpdateCheckResult> Function(String currentVersion)? checkUpdate;
  final Future<bool> Function(String url)? openUrl;
  final Future<void> Function()? startKernel;
  final String? globalExit;
  final void Function(String profileName, Map<String, int?> values)?
  onLatencyCached;

  /// 抽屉右上角 ×：由 AppShell 负责收起。
  final VoidCallback? onClose;

  final Widget Function(Widget speed, Widget updates, Widget runtime)?
  desktopLayout;

  @override
  State<PulsePage> createState() => _PulsePageState();
}

class _PulsePageState extends State<PulsePage> with TickerProviderStateMixin {
  List<String> _allNodes = const [];
  final TextEditingController _searchCtrl = TextEditingController();
  final TextEditingController _customUrlCtrl = TextEditingController();
  String? _node;
  late SpeedSourceChoice _source;

  SpeedTestResult? _speedResult;
  DateTime? _speedAt;
  SpeedTestStage? _speedStage;
  SpeedTestProgress? _speedProgress;
  SpeedTestCancelToken? _speedCancel;
  bool _speedTesting = false;
  bool _tempStartNotified = false;

  Timer? _uptimeTimer;
  Timer? _connTimer;
  int? _connections;
  DateTime _now = DateTime.now();

  bool _checking = false;
  UpdateCheckResult? _updateResult;

  late final AnimationController _float;
  late final AnimationController _backdrop;
  late final AnimationController _enter;
  late final AnimationController _radar;
  bool _reducedMotion = false;
  bool _motionReady = false;

  @override
  void initState() {
    super.initState();
    _allNodes = widget.profile.proxies.map((p) => p.name).toList();
    _node = _allNodes.isEmpty ? null : _allNodes.first;
    final sourceName = widget.prefs.speedTestSourceName;
    final source = SpeedSource.values.firstWhere(
      (value) => value.name == sourceName,
      orElse: () => SpeedSource.fast,
    );
    _source = SpeedSourceChoice(source, widget.prefs.speedTestCustomUrl);
    _customUrlCtrl.text = _source.customUrl;
    _float = AnimationController(vsync: this, duration: kMascotFloatDuration);
    _backdrop = AnimationController(
      vsync: this,
      duration: kPulseBackdropPeriod,
    );
    _enter = AnimationController(
      vsync: this,
      duration: kPulseContentEnterDuration,
    );
    _radar = AnimationController(vsync: this, duration: kPulseRadarPeriod)
      ..value = 1;
    _startRuntimeTimers();
    widget.runtime?.addListener(_onRuntimeChanged);
  }

  @override
  void didUpdateWidget(covariant PulsePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.profile != oldWidget.profile) {
      _allNodes = widget.profile.proxies.map((p) => p.name).toList();
      if (!_allNodes.contains(_node)) _node = _allNodes.firstOrNull;
    }
  }

  /// 内核状态可能在 Pulse 打开后才变化（例如刚点了「启动内核」），
  /// 所以监听 controller，进入运行态时补上运行时长/连接数轮询。
  void _onRuntimeChanged() {
    if (!mounted) return;
    _startRuntimeTimers();
    setState(() => _now = DateTime.now());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduced =
        widget.desktopLayout != null ||
        (MediaQuery.maybeDisableAnimationsOf(context) ?? false);
    if (_motionReady && reduced == _reducedMotion) return;
    _motionReady = true;
    _reducedMotion = reduced;
    if (reduced) {
      _float.stop();
      _backdrop.stop();
      _radar.stop();
      _radar.value = 1;
      _enter.value = 1;
    } else {
      if (!_float.isAnimating) _float.repeat(reverse: true);
      if (!_backdrop.isAnimating) _backdrop.repeat();
      if (!_radar.isAnimating) _radar.repeat();
      _enter.forward(from: 0);
    }
  }

  @override
  void dispose() {
    widget.runtime?.removeListener(_onRuntimeChanged);
    _uptimeTimer?.cancel();
    _connTimer?.cancel();
    _speedCancel?.cancel();
    _float.dispose();
    _backdrop.dispose();
    _enter.dispose();
    _radar.dispose();
    super.dispose();
  }

  bool get _kernelRunning => widget.runtime?.phase == RuntimePhase.running;

  void _startRuntimeTimers() {
    if (!_kernelRunning) {
      _uptimeTimer?.cancel();
      _uptimeTimer = null;
      _connTimer?.cancel();
      _connTimer = null;
      _connections = null;
      return;
    }
    if (_uptimeTimer != null) return;
    _uptimeTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      setState(() => _now = DateTime.now());
    });
    _pollConnections();
    _connTimer = Timer.periodic(
      const Duration(seconds: 3),
      (_) => _pollConnections(),
    );
  }

  Future<void> _pollConnections() async {
    final counter = widget.connectionCount;
    try {
      final value = counter != null
          ? await counter()
          : await widget.runtime?.fetchConnectionCount();
      if (!mounted) return;
      setState(() => _connections = value);
    } catch (_) {
      if (!mounted) return;
      setState(() => _connections = null);
    }
  }

  // ------------------------------------------------------------------ 测速

  List<String> get _filteredNodes {
    final query = _searchCtrl.text.trim().toLowerCase();
    if (query.isEmpty) return _allNodes;
    return [
      for (final name in _allNodes)
        if (name.toLowerCase().contains(query)) name,
    ];
  }

  int? _delayOf(String name) {
    final runtimeDelay = widget.runtime?.delays[name];
    if (runtimeDelay != null) return runtimeDelay;
    return widget.prefs.latenciesOf(widget.profileName)[name];
  }

  bool _approxOf(String name) => widget.runtime?.delayApprox(name) ?? false;

  String? get _customUrlError {
    if (_source.source != SpeedSource.custom) return null;
    final text = _customUrlCtrl.text.trim();
    if (text.isEmpty) return '请输入测速地址';
    if (!_source.hasValidCustomUrl) return '只支持 http/https 地址';
    return null;
  }

  bool get _canStartSpeedTest =>
      !_speedTesting && _node != null && _source.url != null;

  void _selectNode(String name) {
    if (_speedTesting) return;
    setState(() {
      _node = name;
      _speedResult = null;
      _speedAt = null;
      _speedProgress = null;
    });
  }

  void _selectSource(SpeedSource source) {
    if (_speedTesting) return;
    setState(() {
      _source = _source.withSource(source);
      _speedResult = null;
      _speedAt = null;
      _speedProgress = null;
    });
    widget.prefs.setSpeedTestSourceName(_source.source.name);
  }

  void _setCustomUrl(String value) {
    if (_speedTesting) return;
    setState(() {
      _source = _source.withCustomUrl(value);
      _speedResult = null;
      _speedAt = null;
    });
    widget.prefs.setSpeedTestCustomUrl(value.trim());
  }

  Future<void> _startSpeedTest() async {
    final node = _node;
    final test = widget.speedTest;
    final url = _source.url;
    if (node == null || test == null || url == null || _speedTesting) return;
    final token = SpeedTestCancelToken();
    setState(() {
      _speedTesting = true;
      _speedResult = null;
      _speedAt = null;
      _speedProgress = null;
      _speedStage = SpeedTestStage.starting;
      _speedCancel = token;
      _tempStartNotified = false;
    });
    try {
      final result = await test(
        node,
        source: _source,
        cancelToken: token,
        onProgress: (progress) {
          if (!mounted) return;
          setState(() => _speedProgress = progress);
        },
        onStage: (stage) {
          if (!mounted) return;
          if (stage == SpeedTestStage.starting &&
              !_tempStartNotified &&
              !_kernelRunning) {
            _tempStartNotified = true;
            showToast(context, '测速会临时用独立内核，不影响当前配置');
          }
          setState(() => _speedStage = stage);
        },
      );
      if (!mounted) return;
      if (!result.cancelled) {
        setState(() {
          _speedResult = result;
          _speedAt = DateTime.now();
        });
      }
    } catch (error) {
      if (mounted) showToast(context, describeSpeedTestError(error));
    } finally {
      if (mounted) {
        setState(() {
          _speedTesting = false;
          _speedStage = null;
          _speedProgress = null;
          _speedCancel = null;
        });
      }
    }
  }

  void _cancelSpeedTest() {
    _speedCancel?.cancel();
    setState(() {
      _speedStage = SpeedTestStage.restoring;
      _speedResult = null;
      _speedAt = null;
    });
  }

  // ------------------------------------------------------------------ 更新

  Future<void> _checkUpdate() async {
    if (_checking) return;
    final version = widget.appVersion;
    if (version.isEmpty) {
      showToast(context, '读不到当前版本');
      return;
    }
    setState(() => _checking = true);
    try {
      final check = widget.checkUpdate;
      final result = check != null
          ? await check(version)
          : await checkForUpdate(currentVersion: version);
      if (!mounted) return;
      setState(() => _updateResult = result);
      switch (result) {
        case UpdateAvailable():
          await widget.prefs.setLastNotifiedVersion(result.info.version);
        case UpToDate():
          showToast(context, '已是最新版本');
        case UpdateFailed():
          showToast(context, result.failure.message);
      }
    } catch (error) {
      if (!mounted) return;
      showToast(context, '检查更新失败：$error');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
  }

  Future<void> _openLink(String url) async {
    final open = widget.openUrl;
    try {
      final ok = open != null
          ? await open(url)
          : await launchUrl(
              Uri.parse(url),
              mode: LaunchMode.externalApplication,
            );
      if (!ok && mounted) showToast(context, '打不开浏览器');
    } catch (_) {
      if (mounted) showToast(context, '打不开浏览器');
    }
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    if (widget.desktopLayout case final layout?) {
      return layout(
        _speedCard(context),
        _updateCard(context),
        _runtimeCard(context),
      );
    }
    final motion = Motion.of(context);
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final cards = <Widget>[
      if (widget.onClose case final close?)
        _PulseHeader(onClose: close, motion: motion),
      _infoCard(context, motion, disableAnimations),
      _speedCard(context),
      _updateCard(context),
      _runtimeCard(context),
    ];
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: RepaintBoundary(
              child: _PulseBackdrop(
                animation: _backdrop,
                reducedMotion: _reducedMotion,
              ),
            ),
          ),
          SafeArea(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.lg,
                56,
              ),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {},
                child: Column(
                  children: [
                    for (var i = 0; i < cards.length; i++)
                      _PulseIntro(
                        index: i,
                        animation: _enter,
                        reducedMotion: disableAnimations,
                        child: Padding(
                          padding: EdgeInsets.only(top: i == 0 ? 0 : Insets.md),
                          child: cards[i],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoCard(BuildContext context, Motion motion, bool disable) {
    final scheme = Theme.of(context).colorScheme;
    final runtime = widget.runtime;
    final phase = runtime == null ? RuntimePhase.idle : runtime.phase;
    final status = switch (phase) {
      RuntimePhase.running => '内核运行中 ${_uptimeText()}',
      RuntimePhase.starting => '内核启动中',
      RuntimePhase.stopping => '内核停止中',
      RuntimePhase.error => '内核出错',
      RuntimePhase.idle => '未运行',
    };
    void openProject() => unawaited(_openLink(clashDeckProjectUrl));
    return _GlassCard(
      child: Row(
        children: [
          AppInkWell(
            onTap: openProject,
            child: _Mascot(animation: _float, disabled: disable),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppInkWell(
                  onTap: openProject,
                  child: const _GradientWordmark(),
                ),
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: switch (phase) {
                          RuntimePhase.running => scheme.primary,
                          RuntimePhase.starting ||
                          RuntimePhase.stopping => scheme.tertiary,
                          RuntimePhase.error => scheme.error,
                          RuntimePhase.idle => scheme.outline,
                        },
                      ),
                    ),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        '${widget.appVersion} · $status',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: hintStyle(context),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: Insets.sm),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Pill(
              label: widget.profileName,
              color: scheme.onSurfaceVariant,
              dense: true,
            ),
          ),
        ],
      ),
    );
  }

  Widget _speedCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nodes = _filteredNodes;
    final selected = _node;
    final stage = _speedStage;
    final result = _speedResult;
    final progress = _speedProgress;
    final customError = _customUrlError;
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: '节点测速')),
              Text('下载测速', style: hintStyle(context)),
            ],
          ),
          MotionSize(
            child: switch (stage) {
              SpeedTestStage.starting => const _SpeedBanner(
                text: '测速会临时用独立内核，不影响当前配置',
              ),
              SpeedTestStage.waiting => const _SpeedBanner(text: '等待内核就绪…'),
              SpeedTestStage.restoring => const _SpeedBanner(text: '正在恢复连接…'),
              _ => const SizedBox.shrink(),
            },
          ),
          const SizedBox(height: Insets.sm),
          if (_allNodes.isEmpty)
            Text('还没有节点。去「配置」页添加或导入节点后再来测速。', style: hintStyle(context))
          else ...[
            AppSearchField(
              controller: _searchCtrl,
              hint: '搜索节点',
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Insets.sm),
            if (nodes.isEmpty)
              Text('没有匹配的节点', style: hintStyle(context))
            else
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final name in nodes)
                    _SpeedNodeChip(
                      name: name,
                      delay: _delayOf(name),
                      approx: _approxOf(name),
                      selected: name == selected,
                      onTap: _speedTesting ? null : () => _selectNode(name),
                    ),
                ],
              ),
            const SizedBox(height: Insets.sm),
            const Hairline(),
            const SizedBox(height: Insets.sm),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                Text('测速线路', style: monoStyle(context, size: 11)),
                for (final source in SpeedSource.values)
                  ChipShell(
                    selected: _source.source == source,
                    onTap: _speedTesting ? null : () => _selectSource(source),
                    child: Text(
                      SpeedSourceChoice(source).label,
                      style: monoStyle(context, size: 11),
                    ),
                  ),
              ],
            ),
            AnimatedSize(
              duration: Motion.of(context).expand,
              curve: Motion.of(context).enter,
              alignment: Alignment.topCenter,
              child: _source.source == SpeedSource.custom
                  ? Padding(
                      padding: const EdgeInsets.only(top: Insets.sm),
                      child: AppTextField(
                        controller: _customUrlCtrl,
                        hint: 'https://example.com/10mb.bin',
                        error: customError,
                        onChanged: _setCustomUrl,
                      ),
                    )
                  : const SizedBox(width: double.infinity),
            ),
            const SizedBox(height: Insets.sm),
            if (_speedTesting)
              Row(
                children: [
                  Expanded(
                    child: Text(switch (stage) {
                      SpeedTestStage.starting => '正在启动测速内核…',
                      SpeedTestStage.waiting => '等待内核就绪…',
                      SpeedTestStage.downloading => _progressText(progress),
                      SpeedTestStage.restoring => '正在恢复连接…',
                      _ => '准备中…',
                    }, style: hintStyle(context)),
                  ),
                  FilledButton.tonal(
                    onPressed: _cancelSpeedTest,
                    child: const Text('取消'),
                  ),
                ],
              )
            else
              Row(
                children: [
                  Expanded(
                    child: Text(
                      selected == null ? '先选择一个节点' : '本次将测：$selected',
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  FilledButton(
                    onPressed: _canStartSpeedTest ? _startSpeedTest : null,
                    child: Text(result == null ? '开始测速' : '重新测速'),
                  ),
                ],
              ),
            if (result != null) ...[
              const SizedBox(height: Insets.sm),
              _SpeedResultRow(result: result, node: selected ?? ''),
            ],
            if (result != null && !result.ok && !result.cancelled)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: _canStartSpeedTest ? _startSpeedTest : null,
                  child: const Text('重测'),
                ),
              ),
            if (_speedAt != null)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  '上次测速 ${_stamp(_speedAt!)}',
                  style: hintStyle(context),
                ),
              ),
          ],
        ],
      ),
    );
  }

  String _progressText(SpeedTestProgress? progress) {
    if (progress == null) return '正在下载…';
    final mb = progress.bytes / (1024 * 1024);
    return '已下载 ${mb.toStringAsFixed(1)} MB · '
        '${progress.megabytesPerSecond.toStringAsFixed(1)} MB/s';
  }

  Widget _updateCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final result = _updateResult;
    final status = switch (result) {
      UpdateAvailable() => '发现 ${result.info.version}',
      UpToDate() => '已是最新版本',
      UpdateFailed() => result.failure.message,
      null => '最新正式版',
    };
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: '检查更新')),
              Text('当前 ${widget.appVersion}', style: hintStyle(context)),
            ],
          ),
          const SizedBox(height: Insets.xs),
          Row(
            children: [
              Expanded(
                child: AnimatedSwitcher(
                  duration: motion.fast,
                  switchInCurve: motion.enter,
                  switchOutCurve: motion.exit,
                  layoutBuilder: (child, previous) => Stack(
                    alignment: Alignment.centerLeft,
                    children: [...previous, ?child],
                  ),
                  child: Text(
                    status,
                    key: ValueKey(status),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: result is UpdateAvailable
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: Insets.sm),
              TextButton(
                style: TextButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  minimumSize: const Size(0, 32),
                  textStyle: const TextStyle(fontSize: 12.5),
                ),
                onPressed: result is UpdateAvailable
                    ? () => showUpdateDialog(
                        context,
                        result.info,
                        openUrl: widget.openUrl,
                      )
                    : (_checking ? null : _checkUpdate),
                child: Text(
                  result is UpdateAvailable
                      ? '去查看'
                      : (_checking ? '检查中…' : '检查更新'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _runtimeCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final runtime = widget.runtime;
    final phase = runtime == null ? RuntimePhase.idle : runtime.phase;
    final phaseText = switch (phase) {
      RuntimePhase.running => '运行中',
      RuntimePhase.starting => '启动中',
      RuntimePhase.stopping => '停止中',
      RuntimePhase.error => '出错',
      RuntimePhase.idle => '未运行',
    };
    final color = phase == RuntimePhase.running
        ? scheme.primary
        : (phase == RuntimePhase.error ? scheme.error : scheme.outline);
    final exit =
        runtime?.selected['GLOBAL'] ??
        widget.globalExit ??
        (widget.profile.groups.any((g) => g.name == 'DEFAULT')
            ? 'DEFAULT'
            : '—');
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: '运行状态')),
              Pill(label: phaseText, color: color, dense: true),
            ],
          ),
          const SizedBox(height: Insets.sm),
          _Kv(label: '内核状态', value: phaseText, color: color),
          _Kv(label: '运行时长', value: _uptimeText()),
          _Kv(
            label: '连接数',
            value: _connections?.toString() ?? '—',
            leading: _BreathingDot(
              animation: _radar,
              enabled: phase == RuntimePhase.running,
              color: scheme.primary,
            ),
          ),
          _Kv(label: '当前配置', value: widget.profileName),
          _Kv(label: '全局出口', value: exit),
          MotionSize(
            child: phase == RuntimePhase.error && runtime?.lastError != null
                ? Padding(
                    padding: const EdgeInsets.only(top: Insets.sm),
                    child: Text(
                      runtime!.lastError!,
                      style: TextStyle(fontSize: 12, color: scheme.error),
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }

  String _uptimeText() {
    final started = widget.runtime?.startedAt;
    if (started == null) return '—';
    var diff = _now.difference(started);
    if (diff.isNegative) diff = Duration.zero;
    final h = diff.inHours;
    final m = diff.inMinutes.remainder(60);
    final s = diff.inSeconds.remainder(60);
    if (h > 0) return '${h}h ${m}m';
    if (m > 0) return '${m}m ${s}s';
    return '${s}s';
  }

  String _stamp(DateTime time) => pulseSpeedStamp(time);
}

/// 大号渐变态字标：只在 Pulse 层使用，主界面保持克制。
class _GradientWordmark extends StatelessWidget {
  const _GradientWordmark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.centerLeft,
      child: ShaderMask(
        shaderCallback: (bounds) => LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [scheme.primary, scheme.tertiary],
        ).createShader(bounds),
        child: Text(
          'ClashDeck',
          maxLines: 1,
          softWrap: false,
          style: display(24, color: Colors.white),
        ),
      ),
    );
  }
}

/// 叠加层里的磨砂玻璃卡：背景层会透出来，不能再用不透明的 AppCard。
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.windows) {
      return AppCard(padding: const EdgeInsets.all(Insets.lg), child: child);
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.all(Insets.lg),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Colors.white.withValues(alpha: 0.10),
                Colors.white.withValues(alpha: 0.04),
              ],
            ),
            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.28),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }
}

/// 卡片入场：按 40ms 阶梯淡入 + 上移 + 轻微缩放。
class _SpeedBanner extends StatelessWidget {
  const _SpeedBanner({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(Radiuses.sm),
          border: Border.all(color: scheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          text,
          style: TextStyle(fontSize: 11.5, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

class _SpeedResultRow extends StatelessWidget {
  const _SpeedResultRow({required this.result, required this.node});

  final SpeedTestResult result;
  final String node;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ok = result.ok;
    final color = ok ? const Color(0xFF3FB950) : scheme.error;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radiuses.md),
        border: Border.all(color: color.withValues(alpha: 0.28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(node, style: monoStyle(context, size: 11)),
          const SizedBox(height: 4),
          if (ok)
            Text(
              result.summary,
              style: monoStyle(context, size: 15, color: color),
            )
          else
            Text(
              result.failure ?? '测速失败',
              style: TextStyle(fontSize: 12.5, color: color),
            ),
        ],
      ),
    );
  }
}

class _SpeedNodeChip extends StatelessWidget {
  const _SpeedNodeChip({
    required this.name,
    required this.delay,
    required this.approx,
    required this.selected,
    required this.onTap,
  });

  final String name;
  final int? delay;
  final bool approx;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = delay == null ? null : formatDelay(delay, approx: approx);
    return ChipShell(
      selected: selected,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            name,
            style: monoStyle(
              context,
              size: 11,
              color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
            ),
          ),
          if (text != null) ...[
            const SizedBox(width: 5),
            Text(
              text,
              style: monoStyle(
                context,
                size: 10.5,
                color: DelayBadge.colorOf(text, scheme),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _PulseIntro extends StatelessWidget {
  const _PulseIntro({
    required this.index,
    required this.animation,
    required this.reducedMotion,
    required this.child,
  });

  final int index;
  final Animation<double> animation;
  final bool reducedMotion;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (reducedMotion) return child;
    final start = (index * 0.12).clamp(0.0, 0.8);
    final curved = CurvedAnimation(
      parent: animation,
      curve: Interval(start, 1, curve: Curves.easeOutCubic),
    );
    return AnimatedBuilder(
      animation: curved,
      builder: (context, child) {
        final t = curved.value;
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, 16 * (1 - t)),
            child: Transform.scale(scale: 0.98 + 0.02 * t, child: child),
          ),
        );
      },
      child: child,
    );
  }
}

/// 全屏背景层：mesh 渐变缓慢漂移 + 细网格 + 极淡扫描线 + 漂浮像素猫光点。
/// 与内容层分离并包 RepaintBoundary，避免卡片每帧重建。
class _PulseBackdrop extends StatelessWidget {
  const _PulseBackdrop({required this.animation, required this.reducedMotion});

  final Animation<double> animation;
  final bool reducedMotion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return CustomPaint(
      painter: _BackdropPainter(
        animation: animation,
        reducedMotion: reducedMotion,
        base: scheme.surface,
        primary: scheme.primary,
        tertiary: scheme.tertiary,
        secondary: scheme.secondary,
      ),
      child: const SizedBox.expand(),
    );
  }
}

class _BackdropPainter extends CustomPainter {
  _BackdropPainter({
    required this.animation,
    required this.reducedMotion,
    required this.base,
    required this.primary,
    required this.tertiary,
    required this.secondary,
  }) : super(repaint: animation);

  final Animation<double> animation;
  final bool reducedMotion;
  final Color base;
  final Color primary;
  final Color tertiary;
  final Color secondary;

  @override
  void paint(Canvas canvas, Size size) {
    final t = reducedMotion ? 0.35 : animation.value;
    final rect = Offset.zero & size;
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(primary.withValues(alpha: 0.14), base),
            base,
            Color.alphaBlend(tertiary.withValues(alpha: 0.09), base),
          ],
        ).createShader(rect),
    );

    final blobs = <(Offset, double, Color)>[
      (
        Offset(
          size.width * (0.22 + 0.06 * math.sin(t * 2 * math.pi)),
          size.height * (0.18 + 0.04 * math.cos(t * 2 * math.pi)),
        ),
        size.shortestSide * 0.55,
        primary,
      ),
      (
        Offset(
          size.width * (0.82 + 0.05 * math.cos(t * 2 * math.pi + 0.8)),
          size.height * (0.44 + 0.05 * math.sin(t * 2 * math.pi + 0.5)),
        ),
        size.shortestSide * 0.48,
        tertiary,
      ),
      (
        Offset(
          size.width * (0.35 + 0.07 * math.sin(t * 2 * math.pi + 2.1)),
          size.height * (0.86 + 0.03 * math.cos(t * 2 * math.pi + 1.7)),
        ),
        size.shortestSide * 0.42,
        secondary,
      ),
    ];
    for (final (center, radius, color) in blobs) {
      final paint = Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.176), color.withValues(alpha: 0)],
        ).createShader(Rect.fromCircle(center: center, radius: radius));
      canvas.drawCircle(center, radius, paint);
    }

    final grid = Paint()
      ..color = Colors.white.withValues(alpha: 0.03)
      ..strokeWidth = 0.6;
    const step = 36.0;
    for (var x = 0.0; x <= size.width; x += step) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (var y = 0.0; y <= size.height; y += step) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }

    final scan = Paint()..color = Colors.white.withValues(alpha: 0.05);
    for (var y = 0.0; y < size.height; y += 4) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), scan);
    }

    if (!reducedMotion) {
      final particle = Paint()..color = Colors.white.withValues(alpha: 0.5);
      for (var i = 0; i < 10; i++) {
        final seed = i * 0.37;
        final x = size.width * (0.08 + ((seed * 2.7) % 0.86));
        final drift = (t + seed) % 1.0;
        final y = size.height * (0.9 - drift * 0.75);
        final alpha = (0.28 * (1 - drift)).clamp(0.0, 0.28);
        canvas.drawCircle(
          Offset(x, y),
          i.isEven ? 1.6 : 2.4,
          particle..color = Colors.white.withValues(alpha: alpha),
        );
      }
    }

    // 暗色 scrim：保证正文与背景的对比度（顶部浅、底部深）。
    final scrim = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xB405060A), Color(0xE605060A), Color(0xFA05060A)],
        stops: [0.0, 0.45, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, scrim);

    // 四周轻微 vignette，收住画面边缘。
    final vignette = Paint()
      ..shader = const RadialGradient(
        center: Alignment.center,
        radius: 1.05,
        colors: [Colors.transparent, Color(0x59000000)],
        stops: [0.55, 1.0],
      ).createShader(rect);
    canvas.drawRect(rect, vignette);
  }

  @override
  bool shouldRepaint(covariant _BackdropPainter oldDelegate) =>
      oldDelegate.reducedMotion != reducedMotion;
}

class _PulseHeader extends StatelessWidget {
  const _PulseHeader({required this.onClose, required this.motion});

  final VoidCallback onClose;
  final Motion motion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          'PULSE',
          style: monoStyle(context, size: 10, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
        IconButton(
          tooltip: '收起',
          onPressed: onClose,
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.close_rounded, size: 20),
        ),
      ],
    );
  }
}

class _Mascot extends StatelessWidget {
  const _Mascot({required this.animation, required this.disabled});

  final Animation<double> animation;
  final bool disabled;

  @override
  Widget build(BuildContext context) {
    final image = Image.asset(
      'assets/icon/app_icon.png',
      width: 56,
      height: 56,
      cacheWidth: 168,
      filterQuality: FilterQuality.medium,
      errorBuilder: (context, error, stack) => const SizedBox(
        width: 56,
        height: 56,
        child: Icon(Icons.pets, size: 28),
      ),
    );
    if (disabled) return image;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final dy = (animation.value - 0.5) * 4;
        return Transform.translate(offset: Offset(0, dy), child: child);
      },
      child: image,
    );
  }
}

class _Kv extends StatelessWidget {
  const _Kv({
    required this.label,
    required this.value,
    this.color,
    this.leading,
  });

  final String label;
  final String value;
  final Color? color;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 72,
            child: Row(
              children: [
                if (leading != null) ...[leading!, const SizedBox(width: 5)],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: monoStyle(
                context,
                size: 11.5,
                color: color ?? scheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 连接数前的 3s 呼吸圆点，只在运行中动。
class _BreathingDot extends StatelessWidget {
  const _BreathingDot({
    required this.animation,
    required this.enabled,
    required this.color,
  });

  final Animation<double> animation;
  final bool enabled;
  final Color color;

  @override
  Widget build(BuildContext context) {
    if (!enabled) {
      return Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withValues(alpha: 0.3),
        ),
      );
    }
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) {
      return Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color),
      );
    }
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = 0.5 + 0.5 * math.sin(animation.value * math.pi * 2);
        return Container(
          width: 5,
          height: 5,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color.withValues(alpha: 0.35 + 0.55 * t),
          ),
        );
      },
    );
  }
}
