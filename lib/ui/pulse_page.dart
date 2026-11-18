import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/model/profile.dart';
import '../core/update/update_check.dart';
import '../data/app_prefs.dart';
import '../runtime/runtime_controller.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/app_ink.dart';
import 'widgets/selectable_tile.dart';
import 'widgets/select_sheet.dart';

/// 批量测速的注入点（测试用假实现替换真实内核请求）。
typedef PulseMeasure = Future<Map<String, int?>> Function(
  List<String> names, {
  void Function(int done, int total)? onProgress,
  bool Function()? isCancelled,
});

/// 负一屏 Pulse：概览左滑进来的一页，放「状态、测速、更新、运行信息」。
///
/// 刻意不放快捷开关（启动/停止/模式切换仍在概览页），这里只读 + 测速。
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
  });

  final String appVersion;
  final String profileName;
  final Profile profile;
  final AppPrefs prefs;
  final RuntimeController? runtime;
  final PulseMeasure? measure;
  final Future<int?> Function()? connectionCount;
  final Future<UpdateCheckResult> Function(String currentVersion)? checkUpdate;
  final Future<bool> Function(String url)? openUrl;
  final Future<void> Function()? startKernel;
  final String? globalExit;
  final void Function(String profileName, Map<String, int?> values)?
  onLatencyCached;

  @override
  State<PulsePage> createState() => _PulsePageState();
}

class _PulsePageState extends State<PulsePage> with TickerProviderStateMixin {
  late final List<String> _allNodes;
  final Set<String> _selected = <String>{};
  String? _groupFilter;
  Map<String, int?> _results = <String, int?>{};
  DateTime? _lastAt;

  bool _measuring = false;
  bool _cancelled = false;
  int _done = 0;
  int _total = 0;

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
  Timer? _blinkTimer;
  bool _blink = false;

  @override
  void initState() {
    super.initState();
    _allNodes = widget.profile.proxies.map((p) => p.name).toList();
    _selected.addAll(_allNodes);
    _results = widget.prefs.latenciesOf(widget.profileName);
    _lastAt = widget.prefs.lastLatencyAt(widget.profileName);
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
    _blinkTimer = Timer.periodic(const Duration(seconds: 6), (_) {
      if (!mounted) return;
      setState(() => _blink = true);
      Timer(const Duration(milliseconds: 150), () {
        if (mounted) setState(() => _blink = false);
      });
    });
    _startRuntimeTimers();
    widget.runtime?.addListener(_onRuntimeChanged);
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
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
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
    _blinkTimer?.cancel();
    _float.dispose();
    _backdrop.dispose();
    _enter.dispose();
    _radar.dispose();
    super.dispose();
  }

  bool get _kernelRunning => widget.runtime?.phase == RuntimePhase.running;

  void _startRuntimeTimers() {
    _uptimeTimer?.cancel();
    _connTimer?.cancel();
    if (!_kernelRunning) {
      _connections = null;
      return;
    }
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

  List<String> get _visibleNodes {
    final group = _groupFilter;
    if (group == null) return _allNodes;
    final entry = widget.profile.groups.where((g) => g.name == group).toList();
    if (entry.isEmpty) return _allNodes;
    final members = entry.first.members.toSet();
    return _allNodes.where(members.contains).toList();
  }

  List<String> get _selectedVisible =>
      _visibleNodes.where(_selected.contains).toList();

  Future<void> _startMeasure() async {
    final names = _selectedVisible;
    if (names.isEmpty || _measuring) return;
    setState(() {
      _measuring = true;
      _cancelled = false;
      _done = 0;
      _total = names.length;
    });
    final measure = widget.measure;
    final runtime = widget.runtime;
    try {
      final result = measure != null
          ? await measure(
              names,
              onProgress: _onProgress,
              isCancelled: () => _cancelled,
            )
          : await runtime!.testDelays(
              names,
              onProgress: _onProgress,
              isCancelled: () => _cancelled,
            );
      if (!mounted) return;
      setState(() {
        _results = {..._results, ...result};
        _lastAt = DateTime.now();
      });
      await widget.prefs.setLatencies(widget.profileName, result);
      widget.onLatencyCached?.call(widget.profileName, result);
    } catch (error) {
      if (!mounted) return;
      showToast(context, '测速失败：$error');
    } finally {
      if (mounted) setState(() => _measuring = false);
    }
  }

  void _onProgress(int done, int total) {
    if (!mounted) return;
    setState(() {
      _done = done;
      _total = total;
    });
  }

  void _cancelMeasure() {
    if (!_measuring) return;
    setState(() => _cancelled = true);
  }

  Future<void> _startKernel() async {
    final start = widget.startKernel;
    if (start == null) return;
    try {
      await start();
      if (!mounted) return;
      _startRuntimeTimers();
    } catch (error) {
      if (!mounted) return;
      showToast(context, '启动失败：$error');
    }
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

  Future<void> _openRelease(String url) async {
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

  Future<void> _pickGroup() async {
    final groups = widget.profile.groups
        .where((g) => g.members.any(_allNodes.contains))
        .map((g) => g.name)
        .toList();
    final choice = await showSelectSheet<String>(
      context,
      title: '按策略组筛选',
      subtitle: '只影响这一次的测速范围',
      body: (_) => ListView(
        shrinkWrap: true,
        children: [
          SelectableTile(
            title: const Text('全部节点'),
            subtitle: Text('${_allNodes.length} 个', style: hintStyle(context)),
            selected: _groupFilter == null,
            onTap: () => Navigator.of(context).pop(''),
          ),
          for (final name in groups)
            SelectableTile(
              title: Text(name),
              selected: _groupFilter == name,
              onTap: () => Navigator.of(context).pop(name),
            ),
        ],
      ),
    );
    if (choice == null || !mounted) return;
    setState(() => _groupFilter = choice.isEmpty ? null : choice);
  }

  // -------------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final disableAnimations =
        MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final cards = <Widget>[
      _PulseHeader(
        onBack: () => Navigator.of(context).maybePop(),
        motion: motion,
      ),
      _infoCard(context, motion, disableAnimations),
      _latencyCard(context),
      _updateCard(context),
      _runtimeCard(context),
    ];
    return Scaffold(
      // 叠加层：下层主界面仍可见（被 barrier 压暗），这里不能铺不透明底色。
      backgroundColor: const Color(0xFF05060A),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 300) {
            Navigator.of(context).maybePop();
          }
        },
        onVerticalDragEnd: (details) {
          if ((details.primaryVelocity ?? 0) > 500) {
            Navigator.of(context).maybePop();
          }
        },
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
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
              ),
            ),
            Positioned(
              right: Insets.lg,
              bottom: Insets.lg,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: scheme.surface.withValues(alpha: 0.35),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.12),
                    ),
                  ),
                  child: Text('右滑返回', style: hintStyle(context)),
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
                            padding: EdgeInsets.only(
                              top: i == 0 ? 0 : Insets.md,
                            ),
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
    return _GlassCard(
      child: Row(
        children: [
          _Mascot(animation: _float, blink: _blink, disabled: disable),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const _GradientWordmark(),
                const SizedBox(height: 2),
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
          Pill(
            label: widget.profileName,
            color: scheme.onSurfaceVariant,
            dense: true,
          ),
        ],
      ),
    );
  }

  Widget _latencyCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final running = _kernelRunning;
    final visible = _visibleNodes;
    final selected = _selectedVisible;
    final measured = [
      for (final name in _results.keys)
        if (_results[name] != null && _allNodes.contains(name))
          MapEntry(name, _results[name]),
    ]..sort((a, b) => a.value!.compareTo(b.value!));
    final failed = [
      for (final name in _results.keys)
        if (_results[name] == null && _allNodes.contains(name)) name,
    ];
    final hasCache = _lastAt != null || _results.isNotEmpty;
    final showList = running || hasCache;
    final maxMs = measured.isEmpty
        ? 1
        : math.max(1, measured.map((e) => e.value!).reduce(math.max));
    return _GlassCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(child: SectionTitle(title: '节点测速')),
              if (_lastAt != null)
                Text('上次结果 · ${_stamp(_lastAt!)}', style: hintStyle(context)),
            ],
          ),
          if (showList) ...[
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                AppInkWell(
                  onTap: _measuring ? null : _pickGroup,
                  borderRadius: BorderRadius.circular(Radiuses.sm),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 5,
                    ),
                    child: Row(
                      children: [
                        Icon(
                          Icons.filter_alt_outlined,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _groupFilter ?? '全部节点',
                          style: monoStyle(context, size: 11),
                        ),
                        Icon(
                          Icons.expand_more,
                          size: 15,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: _measuring
                      ? null
                      : () {
                          setState(() {
                            if (selected.length == visible.length) {
                              _selected.removeAll(visible);
                            } else {
                              _selected.addAll(visible);
                            }
                          });
                        },
                  child: Text(
                    selected.length == visible.length
                        ? '全选 ${visible.length} 个'
                        : '已选 ${selected.length} 个',
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: Insets.sm),
          if (!running)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: Row(
                children: [
                  Expanded(child: Text('启动内核后可测速', style: hintStyle(context))),
                  if (widget.startKernel != null)
                    FilledButton.tonal(
                      onPressed: _startKernel,
                      child: const Text('启动内核'),
                    ),
                ],
              ),
            ),
          if (_measuring)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: _RadarPulse(
                animation: _radar,
                done: _done,
                total: _total,
                color: scheme.primary,
                onCancel: _cancelMeasure,
              ),
            ),
          if (!_measuring && running)
            Row(
              children: [
                Expanded(
                  child: Text(
                    selected.isEmpty
                        ? '先选择要测速的节点'
                        : '本次将测 ${selected.length} 个节点',
                    style: hintStyle(context),
                  ),
                ),
                _Breathing(
                  animation: _radar,
                  color: scheme.primary,
                  enabled: running && selected.isNotEmpty,
                  child: FilledButton(
                    onPressed: running && selected.isNotEmpty
                        ? _startMeasure
                        : null,
                    child: const Text('开始测速'),
                  ),
                ),
              ],
            ),
          if (measured.isNotEmpty || failed.isNotEmpty) ...[
            const SizedBox(height: Insets.sm),
            const Hairline(),
            for (var i = 0; i < measured.length; i++)
              _LatencyRow(
                key: ValueKey('latency-${measured[i].key}'),
                name: measured[i].key,
                ms: measured[i].value!,
                ratio: measured[i].value! / maxMs,
                highlight: i == 0,
              ),
            for (final name in failed)
              _LatencyRow(
                key: ValueKey('latency-$name'),
                name: name,
                ms: null,
                ratio: 0,
              ),
          ],
        ],
      ),
    );
  }

  Widget _updateCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final result = _updateResult;
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
                child: Text(
                  switch (result) {
                    UpdateAvailable() => '发现 ${result.info.version}',
                    UpToDate() => '已是最新版本',
                    UpdateFailed() => result.failure.message,
                    null => '从 GitHub 读取最新正式版，不会自动下载',
                  },
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
                    ? () => _openRelease(result.info.url)
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
          if (phase == RuntimePhase.error && runtime?.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text(
                runtime!.lastError!,
                style: TextStyle(fontSize: 12, color: scheme.error),
              ),
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

  String _stamp(DateTime time) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}

/// 大号渐变态字标：只在 Pulse 层使用，主界面保持克制。
class _GradientWordmark extends StatelessWidget {
  const _GradientWordmark();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ShaderMask(
      shaderCallback: (bounds) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [scheme.primary, scheme.tertiary],
      ).createShader(bounds),
      child: Text('ClashDeck', style: display(24, color: Colors.white)),
    );
  }
}

/// 叠加层里的磨砂玻璃卡：背景层会透出来，不能再用不透明的 AppCard。
class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
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
  const _PulseHeader({required this.onBack, required this.motion});

  final VoidCallback onBack;
  final Motion motion;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        IconButton(
          tooltip: '返回',
          onPressed: onBack,
          icon: const Icon(Icons.arrow_back_rounded),
        ),
        const SizedBox(width: 2),
        Text(
          'PULSE',
          style: monoStyle(context, size: 10, color: scheme.onSurfaceVariant),
        ),
        const Spacer(),
      ],
    );
  }
}

class _Mascot extends StatelessWidget {
  const _Mascot({
    required this.animation,
    required this.blink,
    required this.disabled,
  });

  final Animation<double> animation;
  final bool blink;
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
        return Transform.translate(
          offset: Offset(0, dy),
          child: Transform.scale(
            scaleY: blink ? 0.16 : 1,
            alignment: Alignment.center,
            child: child,
          ),
        );
      },
      child: image,
    );
  }
}

class _LatencyRow extends StatefulWidget {
  const _LatencyRow({
    super.key,
    required this.name,
    required this.ms,
    required this.ratio,
    this.highlight = false,
  });

  final String name;
  final int? ms;
  final double ratio;
  final bool highlight;

  @override
  State<_LatencyRow> createState() => _LatencyRowState();
}

class _LatencyRowState extends State<_LatencyRow>
    with TickerProviderStateMixin {
  late final AnimationController _shake;
  late final AnimationController _sheen;

  @override
  void initState() {
    super.initState();
    _shake = AnimationController(vsync: this, duration: kLatencyShakeDuration)
      ..value = 1;
    _sheen = AnimationController(vsync: this, duration: kSheenDuration);
    if (widget.ms == null) _shake.forward(from: 0);
    if (widget.highlight) _sheen.forward(from: 0);
  }

  @override
  void didUpdateWidget(covariant _LatencyRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.ms != widget.ms && widget.ms == null) {
      _shake.forward(from: 0);
    }
    if (!oldWidget.highlight && widget.highlight) {
      _sheen.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _shake.dispose();
    _sheen.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ms = widget.ms;
    final color = switch (ms) {
      null => scheme.outline,
      < 200 => const Color(0xFF3FB950),
      < 500 => const Color(0xFFD29922),
      _ => scheme.error,
    };
    final target = ms == null ? 0.0 : widget.ratio.clamp(0.02, 1.0);
    final row = Container(
      height: 44,
      padding: const EdgeInsets.only(right: 2),
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: scheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 5,
            child: Text(
              widget.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12.5),
            ),
          ),
          const SizedBox(width: Insets.sm),
          Expanded(
            flex: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: TweenAnimationBuilder<double>(
                tween: Tween<double>(end: target),
                duration: kLatencyBarDuration,
                curve: Curves.easeOutCubic,
                builder: (context, value, _) => LinearProgressIndicator(
                  value: value,
                  minHeight: 6,
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  valueColor: AlwaysStoppedAnimation<Color>(color),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 64,
            padding: const EdgeInsets.symmetric(vertical: 3),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: color.withValues(alpha: ms == null ? 0.10 : 0.16),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: color.withValues(alpha: 0.35)),
            ),
            child: ms == null
                ? Text('超时', style: monoStyle(context, size: 11, color: color))
                : TweenAnimationBuilder<double>(
                    tween: Tween<double>(end: ms.toDouble()),
                    duration: kLatencyCountDuration,
                    curve: Curves.easeOutCubic,
                    builder: (context, value, _) => Text(
                      '${value.round()} ms',
                      style: monoStyle(context, size: 11, color: color),
                    ),
                  ),
          ),
        ],
      ),
    );
    return AnimatedBuilder(
      animation: _shake,
      builder: (context, child) {
        final t = 1 - _shake.value;
        final dx = math.sin(t * math.pi * 4) * 4 * t;
        return Transform.translate(offset: Offset(dx, 0), child: child);
      },
      child: Stack(
        children: [
          row,
          if (widget.highlight)
            Positioned.fill(
              child: IgnorePointer(child: _Sheen(animation: _sheen)),
            ),
        ],
      ),
    );
  }
}

/// 测速进行中的雷达脉冲：三圈外扩环 + 中心环形进度。
class _RadarPulse extends StatelessWidget {
  const _RadarPulse({
    required this.animation,
    required this.done,
    required this.total,
    required this.color,
    required this.onCancel,
  });

  final Animation<double> animation;
  final int done;
  final int total;
  final Color color;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final progress = total == 0 ? 0.0 : (done / total).clamp(0.0, 1.0);
    return SizedBox(
      height: 150,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: AnimatedBuilder(
              animation: animation,
              builder: (context, _) => CustomPaint(
                painter: _RadarPulsePainter(
                  value: animation.value,
                  progress: progress,
                  color: color,
                  ring: Theme.of(context).colorScheme.outlineVariant,
                ),
              ),
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('已测 $done/$total', style: monoStyle(context, size: 13)),
              const SizedBox(height: Insets.xs),
              TextButton(onPressed: onCancel, child: const Text('取消')),
            ],
          ),
        ],
      ),
    );
  }
}

class _RadarPulsePainter extends CustomPainter {
  const _RadarPulsePainter({
    required this.value,
    required this.progress,
    required this.color,
    required this.ring,
  });

  final double value;
  final double progress;
  final Color color;
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final maxR = size.shortestSide * 0.42;
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (var i = 0; i < 3; i++) {
      final t = (value + i / 3) % 1;
      final r = maxR * (0.34 + 0.66 * t);
      canvas.drawCircle(
        center,
        r,
        base..color = color.withValues(alpha: (1 - t) * 0.35),
      );
    }
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..color = ring.withValues(alpha: 0.35);
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.26),
      -math.pi / 2,
      math.pi * 2,
      false,
      track,
    );
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: maxR * 0.26),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RadarPulsePainter old) =>
      old.value != value ||
      old.progress != progress ||
      old.color != color ||
      old.ring != ring;
}

/// 「开始测速」按钮的呼吸光晕。
class _Breathing extends StatelessWidget {
  const _Breathing({
    required this.animation,
    required this.color,
    required this.enabled,
    required this.child,
  });

  final Animation<double> animation;
  final Color color;
  final bool enabled;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (!enabled) return child;
    final reduced = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduced) return child;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = 0.5 + 0.5 * math.sin(animation.value * math.pi * 2);
        return DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.10 + 0.14 * t),
                blurRadius: 14 + 8 * t,
                spreadRadius: 1 + 2 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}

/// 第一名结果的一次性扫光。
class _Sheen extends StatelessWidget {
  const _Sheen({required this.animation});

  final Animation<double> animation;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final t = animation.value;
        return FractionalTranslation(
          translation: Offset(-1.2 + 2.4 * t, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.0),
                  Colors.white.withValues(alpha: 0.16 * (1 - t)),
                  Colors.white.withValues(alpha: 0.0),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// 运行状态的两列 key-value：标签小号灰、值右对齐等宽。
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
