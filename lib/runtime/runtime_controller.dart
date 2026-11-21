import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

import '../core/edit/import_rules.dart';
import '../core/model/app_settings.dart';
import '../core/net/fetch_text.dart';
import '../core/validate/validator.dart';
import '../data/rule_cache.dart';
import '../core/yaml/yaml_doc.dart';
import 'geodata.dart';
import 'mihomo_api.dart';
import 'delay_targets.dart';
import 'runtime_config.dart';
import 'runtime_template.dart';
import 'speed_test.dart';
import 'speed_test_config.dart';
import 'tcp_delay_probe.dart';
import 'windows_kernel.dart';

/// 内核 + VPN 的生命周期阶段。
enum RuntimePhase { idle, starting, running, stopping, error }

typedef RuntimeTrafficSample = ({DateTime at, int up, int down});

/// 运行期控制器：把 Dart 侧的配置生成、REST 观察、Android 侧 VpnService
/// 与子进程编排串起来。
///
/// 数据流：
///   1. Dart 调 `start` → Kotlin 申请 VPN 授权并建立 TUN；
///   2. Kotlin 拿到 fd 后反向调 Dart 的 `buildRuntimeConfig`，Dart 用真实 fd
///      生成运行配置返回（配置生成逻辑只有这一处）；
///   3. Kotlin 写盘并拉起内核，状态通过 `onRuntimeState` 推回 Dart；
///   4. Dart 之后用 REST（[api]）观察 / 热重载 / 切换节点。
class RuntimeController extends ChangeNotifier {
  RuntimeController({
    required this.configProvider,
    this.settingsProvider,
    MethodChannel? channel,
    this.port = 9090,
    this.secret,
    this.pollInterval = const Duration(seconds: 3),
    this.androidOverride,
    this.workDirProvider,
    this.delayProbe,
    this.tcpConnector,
    this.displayProvider,
    this.pruneSavedExit,
    this.pruneSavedGlobalExit,
    this.apiOverride,
    this.windowsKernel,
  }) : _channel = channel ?? const MethodChannel(channelName) {
    if (windowsKernel == null) _channel.setMethodCallHandler(_handleDartCall);
  }

  /// 通道名必须与 `android/app/src/main/kotlin/dev/clashdeck/RuntimeBridge.kt` 一致。
  static const String channelName = 'dev.clashdeck/runtime';

  /// 只有 Android 才有 VpnService 实现。测试里可用 [androidOverride] 覆盖。
  static bool get supported => Platform.isAndroid;

  final YamlDoc Function() configProvider;

  /// 运行参数（代理模式 / 分应用名单 / TUN MTU）的来源。缺省按默认设置。
  final AppSettings Function()? settingsProvider;
  final MethodChannel _channel;
  final bool? androidOverride;
  final Future<String> Function()? workDirProvider;
  final WindowsKernel? windowsKernel;

  /// 测试注入：替代真实 REST 的单节点测速。
  final Future<int?> Function(String name)? delayProbe;

  /// 测试注入：替代真实 socket 的 TCP 连接工厂。
  final TcpConnector? tcpConnector;

  /// 供 Kotlin 快照用的展示信息（当前配置名 / 全局出口）。
  /// 磁贴、通知、小组件在 Flutter 不在时只能读这份快照。
  final ({String profile, String exit}) Function()? displayProvider;

  /// 设置里记住的组出口已经失效（组不存在 / 节点不在组里）时，把它从
  /// sidecar 删掉，避免每次启动都重放一次注定 404 的 selectProxy。
  final void Function(String group, String? node)? pruneSavedExit;

  /// 同上，针对全局出口 GLOBAL。
  final void Function()? pruneSavedGlobalExit;

  /// 测试注入：替代真实 REST 的 [MihomoApi]。
  final MihomoApi? apiOverride;

  /// 轮询是否在跑（测试用来断言 idle 分支也会启动轮询）。
  @visibleForTesting
  bool get polling => _pollTimer != null;
  final int port;
  final String? secret;
  final Duration pollInterval;
  int? _windowsPort;
  int _windowsOperation = 0;
  bool _windowsClosing = false;

  /// 测速期间临时内核使用的最小配置；为 null 时用当前配置。
  YamlDoc? _speedTestConfig;

  /// 临时测速内核期间不覆盖用户配置的冷启动快照。
  bool _tempConfigActive = false;

  /// 构建/校验内核配置时的来源：临时测速配置优先。
  YamlDoc _activeConfig() => _speedTestConfig ?? configProvider();

  RuntimePhase _phase = RuntimePhase.idle;
  String? _lastError;
  ValidationReport? _startupReport;
  int? _pid;
  String? _workDir;
  int _lastFd = 0;
  String? _startedTunStack;
  List<String> _logs = const [];
  Map<String, String> _selected = const {};
  Map<String, List<String>> _members = const {};
  Map<String, int?> _delays = const {};

  /// 通过 TCP 探针测出的近似值（内核未运行或回退时使用）；UI 用 `≈` 标记。
  Set<String> _approxDelays = const <String>{};

  /// 本次启动是否已经把设置里的全局出口应用过（只做一次）。
  bool _globalExitApplied = false;

  /// 规则集缓存缺失（补拉也失败）的个数，供 UI 提示「N 个规则集未生效」。
  int _missingRuleCaches = 0;

  /// 是否有一次测速在跑（自动或手动），UI 用来禁用按钮/显示进度。
  bool _delayTesting = false;

  /// 本次启动是否已经自动测过一轮。
  bool _autoDelayed = false;
  int _up = 0;
  int _down = 0;
  RuntimeTrafficSample? _latestTraffic;

  /// VpnService 是否在运行（Kotlin 侧 `ClashVpnService.running`）。
  bool _serviceRunning = false;

  Timer? _pollTimer;

  /// 本次启动时间；内核未运行时为 null。
  DateTime? _startedAt;
  StreamSubscription<({int up, int down})>? _trafficSub;
  MihomoApi? _trafficClient;
  bool _disposed = false;

  /// 配置保存后的自动重启：500ms 内多次保存只重启一次。
  Timer? _restartTimer;
  bool _restarting = false;
  String? _restartReason;

  RuntimePhase get phase => _phase;

  /// 测试专用：驱动内部状态机（真实启动依赖 Android 通道）。
  @visibleForTesting
  void debugSetPhase(RuntimePhase phase) {
    _phase = phase;
  }

  String? get lastError => _lastError;

  /// 启动前校验未通过时的 issue 列表（供「仍然启动」弹窗展示）。
  ValidationReport? get startupReport => _startupReport;
  int? get pid => _pid;
  String? get workDir => _workDir;

  /// 内核日志尾部（最多 500 行，Android 侧缓冲）。
  List<String> get logs => _logs;

  /// 运行期组 → 当前选中节点。
  Map<String, String> get selected => _selected;

  /// 运行期组 → 可选成员。
  Map<String, List<String>> get members => _members;

  /// 延迟测试结果：节点名 → 毫秒（null 表示超时/失败）。
  Map<String, int?> get delays => _delays;

  /// [name] 的最近一次延迟是否来自 TCP 探针（近似值，UI 加 `≈`）。
  bool delayApprox(String name) => _approxDelays.contains(name);

  /// 当前所有近似延迟的节点名。
  Set<String> get approxDelays => _approxDelays;

  /// 本次启动时间；内核未运行时为 null。
  DateTime? get startedAt => _startedAt;

  bool get delayTesting => _delayTesting;

  int get up => _up;
  int get down => _down;
  RuntimeTrafficSample? get latestTraffic => _latestTraffic;

  /// 本次启动时补拉也失败的规则集缓存个数（UI 用来提示「N 个规则集未生效」）。
  int get missingRuleCaches => _missingRuleCaches;

  bool get isBusy =>
      _phase == RuntimePhase.starting || _phase == RuntimePhase.stopping;

  int get _controllerPort => _windowsPort ?? port;

  MihomoApi get api =>
      apiOverride ??
      MihomoApi(host: '127.0.0.1', port: _controllerPort, secret: secret);

  // ------------------------------------------------------------------ 生命周期

  @override
  void dispose() {
    _disposed = true;
    _restartTimer?.cancel();
    _stopPolling();
    if (windowsKernel == null) _channel.setMethodCallHandler(null);
    if (windowsKernel != null && !_windowsClosing) {
      unawaited(shutdownWindows().catchError((Object _) {}));
    }
    super.dispose();
  }

  Future<void> shutdownWindows() async {
    final windows = windowsKernel;
    if (windows == null || _windowsClosing) return;
    _windowsClosing = true;
    _windowsOperation++;
    _restartTimer?.cancel();
    _clearWindowsSession();
    await windows.dispose();
  }

  /// 是否正在执行「保存后自动重启」。UI 可以据此显示「正在重启」。
  bool get restarting => _restarting;

  /// 配置保存后按需重启内核。
  ///
  /// 只有内核正在运行（或正在启动）时才动；500ms 内的多次调用合并成一次，
  /// 避免连续编辑（例如一次导入写入多条规则）触发多次 stop/start。
  /// 不改变 [phase] 之外的状态；失败时走 [lastError]。
  Future<void> restartIfRunning({
    String reason = '配置已保存',
    Duration debounce = const Duration(milliseconds: 500),
  }) async {
    if (_disposed || (windowsKernel != null && _tempConfigActive)) return;
    if (_phase != RuntimePhase.running && _phase != RuntimePhase.starting) {
      return;
    }
    _restartReason = reason;
    if (_restarting) return;
    if (_restartTimer?.isActive ?? false) return;
    _restartTimer = Timer(debounce, () {
      unawaited(_performRestart());
    });
  }

  Future<void> _performRestart() async {
    if (_disposed || _restarting) return;
    // 刚点启动就保存：等内核真正 running 再重启，否则 stop 会打断授权流程。
    final deadline = DateTime.now().add(const Duration(seconds: 8));
    while (_phase == RuntimePhase.starting &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      if (_disposed) return;
    }
    if (_phase != RuntimePhase.running) return;
    _restarting = true;
    final reason = _restartReason ?? '配置已保存';
    notifyListeners();
    try {
      await stop();
      // stop 只负责发指令，真正落地要等 onRuntimeState 把 phase 置回 idle。
      final waitUntil = DateTime.now().add(const Duration(seconds: 5));
      while (_phase == RuntimePhase.stopping &&
          DateTime.now().isBefore(waitUntil)) {
        await Future<void>.delayed(const Duration(milliseconds: 80));
        if (_disposed) return;
      }
      final ok = await start(force: true);
      if (!ok && _lastError == null) {
        _setError('$reason后内核重启失败');
      }
    } finally {
      _restarting = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// 配置里 `type: file` 的规则集，缓存文件丢了就用镜像链补拉一次。
  ///
  /// 失败不阻塞启动：内核只是少这几条规则，个数留给 UI 提示。
  Future<void> _backfillRuleCaches() async {
    _missingRuleCaches = 0;
    try {
      final providers = configProvider().plainAt(['rule-providers']);
      if (providers is! Map) return;
      RuleCache? cache;
      var missing = 0;
      for (final entry in providers.entries) {
        final value = entry.value;
        if (value is! Map || '${value['type']}' != 'file') continue;
        final path = value['path'];
        if (path is! String || path.isEmpty) continue;
        if (await File(path).exists()) continue;
        cache ??= await RuleCache.open();
        if (!await _refillRuleCache(cache, '${entry.key}', path)) missing += 1;
      }
      _missingRuleCaches = missing;
      if (missing > 0) notifyListeners();
    } catch (_) {
      // 补拉纯属兜底，任何异常都不该挡住启动。
    }
  }

  Future<bool> _refillRuleCache(RuleCache cache, String id, String path) async {
    final url = await cache.sourceUrl(id);
    if (url == null || url.isEmpty) return false;
    try {
      final fetched = await fetchTextWithMirrors(url, attemptsPerMirror: 1);
      final body = parseRuleProviderBody(fetched.text, url: fetched.url);
      if (body == null) return false;
      final text = ruleCacheBody(body.entries, body.behavior);
      final target = File(path);
      if (target.path == cache.pathFor(id)) {
        await cache.write(id, text, sourceUrl: url);
      } else {
        await target.parent.create(recursive: true);
        await target.writeAsString(text, flush: true);
      }
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 启动内核。返回 false 表示被启动前校验拦下（issues 在 [startupReport]），
  /// 没有真正 spawn；[force] 用于用户在弹窗里确认「仍然启动」。
  Future<bool> start({bool force = false, String? proxyModeOverride}) async {
    if (_disposed || _windowsClosing) return false;
    final windows = windowsKernel;
    if (windows == null && !(androidOverride ?? supported)) {
      _setError('运行内核只支持 Android 设备');
      return false;
    }
    if (_phase == RuntimePhase.starting || _phase == RuntimePhase.running) {
      return true;
    }
    _lastError = null;
    _startupReport = null;
    _globalExitApplied = false;
    _autoDelayed = false;
    _delayTesting = false;
    final operation = ++_windowsOperation;
    _setPhase(RuntimePhase.starting);
    try {
      // 先做语义自检：组成员/规则目标/规则集引用不存在时 mihomo 会直接退出，
      // 与其让用户看到「启动失败」再猜，不如在 spawn 前拦下并列出问题。
      final config = _activeConfig();
      if (!force) {
        final report = ConfigValidator.validate(config);
        if (report.hasErrors) {
          _startupReport = report;
          _setError('配置无法启动：${report.errors.length} 个错误');
          return false;
        }
      }
      _workDir ??= windows != null
          ? (await windows.workDir).path
          : await (workDirProvider?.call() ?? _resolveWorkDir());
      // 先把 GEOIP/GEOSITE 数据铺进工作目录：内核缺数据会同步去 GitHub 下载，
      // 国内基本必定超时，带 GEOIP 规则的配置会直接启动失败。
      await Geodata.ensure(Directory(_workDir!));
      // 换机/清数据后 `type: file` 的规则集会找不到文件，这里先补一次；
      // 补不上也不阻塞启动，只把个数报给 UI。
      await _backfillRuleCaches();
      if (windows != null) {
        if (_disposed || operation != _windowsOperation) return false;
        _windowsPort = await WindowsKernel.controllerPort(excluding: proxyPort);
        if (_disposed || operation != _windowsOperation) return false;
        final probe = MihomoApi(
          host: '127.0.0.1',
          port: _controllerPort,
          secret: secret,
          timeout: const Duration(milliseconds: 800),
        );
        final int pid;
        try {
          pid = await windows.start(
            yaml: _buildRuntimeYaml(0),
            proxyPort: proxyPort,
            ready: probe.ping,
            onExit: (exitCode) {
              if (operation != _windowsOperation) return;
              _clearWindowsSession();
              final tail = windows.logs(1).firstOrNull;
              _setError(tail ?? 'mihomo 已退出（$exitCode）');
            },
          );
        } finally {
          probe.close();
        }
        if (_disposed || operation != _windowsOperation) return false;
        _pid = pid;
        _setPhase(RuntimePhase.running);
        _startPolling();
        _subscribeTraffic();
        unawaited(_refreshRuntimeView());
        return true;
      }
      final settings = settingsProvider?.call() ?? AppSettings.defaults;
      final display = displayProvider?.call();
      final rawMtu = config.plainAt(['tun', 'mtu']);
      final startArgs = <String, Object?>{
        ...settings.toStartArgs(),
        'proxyMode': ?proxyModeOverride,
      };
      await _channel.invokeMethod<Map<Object?, Object?>>('start', {
        'workDir': _workDir,
        'port': port,
        'secret': secret,
        'mtu': rawMtu is num ? rawMtu.toInt() : 9000,
        // system / mixed 栈要在网卡上 bind 内核算出来的 tun 地址，这里把同一个
        // 地址交给 Kotlin 建网卡（gVisor 不看地址，但写了也无害）。
        'tunAddress': RuntimeConfig.tunAddressFor(config),
        'tunStack': RuntimeConfig.tunStackFor(config),
        // 只有 YAML 里 ipv6: true 才让 VpnService 加 v6 地址/路由，否则 v6
        // 流量会被吸进 tun 后丢弃，部分网络下表现为「连不上」。
        'ipv6': config.plainAt(['ipv6']) == true,
        'profileName': display?.profile ?? '',
        'globalExit': display?.exit ?? '',
        ...startArgs,
      });
      // 系统授权对话框由 Activity 处理，结果通过 onRuntimeState 回来。
      return true;
    } catch (error) {
      if (windows != null && operation != _windowsOperation) return false;
      _setError('启动失败：$error');
      return false;
    }
  }

  Future<void> stop() async {
    if (_phase == RuntimePhase.idle) return;
    _setPhase(RuntimePhase.stopping);
    _autoDelayed = false;
    try {
      final windows = windowsKernel;
      if (windows != null) {
        _windowsOperation++;
        await windows.stop();
        _clearWindowsSession();
        _lastError = null;
        _setPhase(RuntimePhase.idle);
        return;
      }
      await _channel.invokeMethod<void>('stop');
    } catch (error) {
      _setError('停止失败：$error');
    }
  }

  void _clearWindowsSession() {
    _stopPolling();
    _pid = null;
    _up = 0;
    _down = 0;
    _latestTraffic = null;
    _selected = const {};
    _members = const {};
  }

  /// VpnService 是否在运行（Kotlin 侧 ClashVpnService.running）。
  ///
  /// 与 [phase] 不同：phase 看内核进程，serviceRunning 看 VPN 服务；
  /// 诊断面板用它区分「服务没起来」和「内核起来了但隧道没接管」。
  bool get serviceRunning => _serviceRunning;

  /// Android 13+ 常驻通知的运行时授权状态。
  ///
  /// 查询失败（旧平台 / 未注册通道）时按已授权处理，避免把平台异常显示成
  /// 「权限未开启」误导用户；授权与否不阻塞内核启动。
  Future<bool> notificationPermission() async {
    try {
      final granted = await _channel.invokeMethod<bool>(
        'notificationPermission',
      );
      return granted ?? true;
    } catch (_) {
      return true;
    }
  }

  /// 跳系统通知设置（Android 8+ 直达本应用的通知页）。
  Future<void> openNotificationSettings() async {
    try {
      await _channel.invokeMethod<void>('openNotificationSettings');
    } catch (_) {
      // 平台不支持时静默失败，用户仍可进系统设置手动开启。
    }
  }

  /// 从 Android 侧同步一次真实状态（进入页面时用）。
  Future<void> refreshStatus() async {
    if (windowsKernel != null) {
      if (_phase == RuntimePhase.running) await _refreshRuntimeView();
      return;
    }
    if (!(androidOverride ?? supported)) return;
    try {
      final status = await _channel.invokeMethod<Map<Object?, Object?>>(
        'status',
      );
      if (status == null) {
        await loadLogs();
        return;
      }
      await applyStatus(status);
    } catch (_) {
      // 通道异常时保持现状。
    }
  }

  /// 把 Android 侧 `status` 的快照对齐到控制器状态。
  ///
  /// 独立出来便于单测：不依赖 MethodChannel 的 mock 时序。
  @visibleForTesting
  Future<void> applyStatus(Map<Object?, Object?> status) async {
    try {
      _pid = (status['pid'] as num?)?.toInt();
      final error =
          (status['error'] as String?) ?? (status['errorText'] as String?);
      final kernelState = status['kernelState'] as String?;
      _serviceRunning =
          status['serviceRunning'] == true || status['running'] == true;
      // 以内核进程为准：即便服务的静态标记没更新，只要有 pid 就说明内核活着。
      final running =
          status['running'] == true || ((_pid ?? 0) > 0 && error == null);
      if (running) {
        // 内核在跑就以内核为准：之前留下的操作错误（例如重放旧出口的 404）
        // 不能把 phase 永久钉在 error 上。
        _lastError = null;
        _setPhase(RuntimePhase.running);
        unawaited(_refreshRuntimeView());
        _startPolling();
      } else if (error != null) {
        _lastError = error;
        _phase = RuntimePhase.error;
      } else if (kernelState == 'running' && _phase != RuntimePhase.running) {
        // App 冷启动后被打开：磁贴/小组件可能已经拉起了内核，这里对齐而不是
        // 假设「刚启动 = 未运行」。
        _lastError = null;
        _setPhase(RuntimePhase.running);
        unawaited(_refreshRuntimeView());
        _startPolling();
      } else if (kernelState == 'starting') {
        _setPhase(RuntimePhase.starting);
      } else if (kernelState == 'stopping') {
        _setPhase(RuntimePhase.stopping);
      } else if (_phase != RuntimePhase.starting && kernelState != 'running') {
        // 内核确实没跑：清掉残留的 pid/启动时间与旧日志，避免 UI 显示幽灵进程。
        final stale = (_pid ?? 0) > 0 || _phase == RuntimePhase.running;
        _pid = null;
        _lastError = null;
        _phase = RuntimePhase.idle;
        if (stale) {
          _startedAt = null;
          _logs = <String>[];
          _stopPolling();
        }
      }
      // 服务标记或 pid 还在：即使还没收到 running，也要轮询等内核应答。
      if (!running &&
          _phase == RuntimePhase.idle &&
          (_serviceRunning || (_pid ?? 0) > 0)) {
        _startPolling();
      }
      await loadLogs();
      notifyListeners();
    } catch (_) {
      // 通道异常时保持现状。
    }
  }

  Future<List<String>> loadLogs({int limit = 300}) async {
    final windows = windowsKernel;
    if (windows != null) return windows.logs(limit);
    if (!supported) return _logs;
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('logs', limit);
      _logs = raw?.map((line) => '$line').toList(growable: false) ?? const [];
      notifyListeners();
    } catch (_) {
      // 忽略
    }
    return _logs;
  }

  Future<void> clearLogs() async {
    if (windowsKernel case final windows?) {
      windows.clearLogs();
      return;
    }
    if (!supported) return;
    try {
      await _channel.invokeMethod<void>('clearLogs');
      _logs = const [];
      notifyListeners();
    } catch (_) {
      // 忽略
    }
  }

  // -------------------------------------------------------------------- 热重载

  /// 配置改完后让内核热重载。
  ///
  /// 用 `PUT /configs` 的 payload 直接推整份运行配置：tun 段与启动时完全一致
  /// （同一个 fd），mihomo 会比较 listener 选项并复用现有 TUN，不会关掉我们的 fd。
  Future<bool> reloadConfig() async {
    if (_phase != RuntimePhase.running) return false;
    final client = api;
    try {
      final text = _buildRuntimeYaml(_lastFd);
      await client.loadPayload(text);
      unawaited(_refreshRuntimeView());
      return true;
    } catch (error) {
      _setError('热重载失败：$error');
      return false;
    } finally {
      client.close();
    }
  }

  /// 运行时切换某个策略组选中的节点。
  ///
  /// [quiet] 为 true 时用于「重放上次选择」：失败不写全局错误条（那是操作
  /// 提示，不是内核故障），只刷新一次真实状态。
  Future<bool> selectNode(
    String group,
    String node, {
    bool quiet = false,
  }) async {
    final client = api;
    try {
      await client.selectProxy(group, node);
      if (_disposed) return false;
      _selected = {..._selected, group: node};
      if (!quiet && (_lastError?.startsWith('切换节点失败：') ?? false)) {
        _lastError = null;
      }
      notifyListeners();
      return true;
    } catch (error) {
      if (_disposed) return false;
      if (quiet) {
        unawaited(_refreshRuntimeView());
      } else {
        _lastError = '切换节点失败：$error';
        notifyListeners();
      }
      return false;
    } finally {
      client.close();
    }
  }

  /// 本地 HTTP 代理端口（运行配置里的 `mixed-port`，缺省 7890）。
  int get proxyPort => RuntimeConfig.proxyPortFor(_activeConfig());

  /// 仅端口模式临时启动：不申请 VPN，也不需要授权。
  ///
  /// 只用于「内核没跑时的下载测速」；结束后由调用方 [stop] 关闭。
  Future<bool> startPortOnly() async {
    if (_phase == RuntimePhase.running || _phase == RuntimePhase.starting) {
      return true;
    }
    return start(proxyModeOverride: 'port');
  }

  /// 等内核进入 running；超时或 error 返回 false。
  Future<bool> waitUntilRunning({
    Duration timeout = const Duration(seconds: 15),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) return false;
      if (_phase == RuntimePhase.running) return true;
      if (_phase == RuntimePhase.error) return false;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return _phase == RuntimePhase.running;
  }

  /// 关掉本次临时启动的内核，并等它落地（最多 5s）。
  Future<void> _stopTemporaryKernel() async {
    if (_phase == RuntimePhase.idle) return;
    await stop();
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (_disposed) return;
      if (_phase == RuntimePhase.idle || _phase == RuntimePhase.error) return;
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
  }

  /// 单节点下载测速：临时用独立最小配置起一个 port-only 内核，测完恢复。
  ///
  /// 不依赖用户配置里的策略组，也不改动用户配置；原本在跑的内核会先停下，
  /// 测完用原配置重新启动。临时配置绝不写入冷启动模板。
  Future<SpeedTestResult> runSpeedTest(
    String node, {
    SpeedSourceChoice source = SpeedSourceChoice.defaultChoice,
    SpeedDownloader? downloader,
    void Function(SpeedTestProgress progress)? onProgress,
    void Function(SpeedTestStage stage)? onStage,
    SpeedTestCancelToken? cancelToken,
  }) async {
    final url = source.url;
    if (url == null) {
      return SpeedTestResult.failed('自定义地址不合法');
    }
    final wasActive =
        _phase == RuntimePhase.running || _phase == RuntimePhase.starting;
    final String tempYaml;
    try {
      tempYaml = buildSpeedTestConfig(configProvider(), nodeName: node);
    } on SpeedTestConfigException catch (error) {
      return SpeedTestResult.failed(error.message);
    }
    final session = SpeedTestSession(
      downloader: downloader ?? SpeedDownloader(),
      kernelReady: () => false,
      startTemporary: () async {
        await _stopTemporaryKernel();
        _speedTestConfig = YamlDoc.parse(tempYaml);
        _tempConfigActive = true;
        final started = await start(proxyModeOverride: 'port', force: true);
        if (!started) {
          _speedTestConfig = null;
          _tempConfigActive = false;
          return false;
        }
        return waitUntilRunning();
      },
      stopTemporary: () async {
        await _stopTemporaryKernel();
        _speedTestConfig = null;
        _tempConfigActive = false;
      },
      proxyPort: () async => _phase == RuntimePhase.running ? proxyPort : null,
      prepareProxy: (_) async => true,
      restoreProxy: () async {},
    );
    try {
      return await session.run(
        node,
        url: url,
        onProgress: onProgress,
        onStage: onStage,
        cancelToken: cancelToken,
      );
    } finally {
      if (_tempConfigActive) {
        await _stopTemporaryKernel();
        _speedTestConfig = null;
        _tempConfigActive = false;
      }
      if (wasActive && !_disposed) {
        final restarted = await start(force: true);
        if (restarted) await waitUntilRunning();
      }
    }
  }

  /// 并发测一批节点的延迟，返回 节点名 → 毫秒（超时/失败为 null）。
  ///
  /// 通道选择：
  /// - 注入了 [delayProbe]（测试或 Pulse 注入）时优先使用；
  /// - 内核 running / starting 时走 mihomo `/proxies/{name}/delay`；
  /// - 内核没跑、或内核通道报错（刚启动 API 还没监听）时，用 TCP 探针测
  ///   `server:port`，结果标记为近似值（UI 显示 `≈`）。
  ///
  /// [isCancelled] 返回 true 时停止派发新任务，已发出的请求会自然结束。
  Future<Map<String, int?>> testDelays(
    List<String> names, {
    int concurrency = 4,
    String url = 'http://www.gstatic.com/generate_204',
    int timeoutMs = 5000,
    void Function(int done, int total)? onProgress,
    bool Function()? isCancelled,
  }) async {
    final results = <String, int?>{};
    final total = names.length;
    final targets = tcpTargetsFrom(configProvider());
    var next = 0;
    var done = 0;
    final limit = concurrency < 1 ? 1 : concurrency;
    _delayTesting = total > 0;
    if (!_disposed) notifyListeners();
    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        final index = next++;
        if (index >= total) return;
        final name = names[index];
        final measured = await _measureOne(
          name,
          target: targets[name],
          url: url,
          timeoutMs: timeoutMs,
          isCancelled: isCancelled,
        );
        results[name] = measured.value;
        done += 1;
        _delays = {..._delays, name: measured.value};
        final approx = {..._approxDelays};
        if (measured.approx) {
          approx.add(name);
        } else {
          approx.remove(name);
        }
        _approxDelays = approx;
        if (!_disposed) notifyListeners();
        onProgress?.call(done, total);
      }
    }

    try {
      await Future.wait([
        for (var i = 0; i < limit && i < total; i++) worker(),
      ]);
    } finally {
      _delayTesting = false;
      if (!_disposed) notifyListeners();
    }
    return results;
  }

  /// 该阶段是否走内核 REST 的精确延迟（starting 也试一次，失败再回退 TCP）。
  static bool kernelDelayChannel(RuntimePhase phase) =>
      phase == RuntimePhase.running || phase == RuntimePhase.starting;

  /// 单个节点的一次测量：返回毫秒值与「是否 TCP 近似」。
  Future<({int? value, bool approx})> _measureOne(
    String name, {
    ({String host, int port})? target,
    required String url,
    required int timeoutMs,
    bool Function()? isCancelled,
  }) async {
    final probe = delayProbe;
    if (probe != null) {
      try {
        return (value: await probe(name), approx: false);
      } catch (_) {
        return (value: null, approx: false);
      }
    }
    final viaKernel = kernelDelayChannel(_phase);
    if (viaKernel) {
      final client = api;
      try {
        final value = await client.delay(name, url: url, timeoutMs: timeoutMs);
        return (value: value, approx: false);
      } catch (_) {
        // starting 时 API 可能还没监听：不直接判超时，回退 TCP 一次。
      } finally {
        client.close();
      }
    }
    final tcp = await _tcpDelay(target, isCancelled: isCancelled);
    return (value: tcp, approx: tcp != null);
  }

  Future<int?> _tcpDelay(
    ({String host, int port})? target, {
    bool Function()? isCancelled,
  }) async {
    if (target == null) return null;
    final result = await probeTcpDelay(
      target.host,
      target.port,
      connector: tcpConnector,
      isCancelled: isCancelled,
    );
    return result?.milliseconds;
  }

  /// 当前连接数（`/connections` 的条数）；内核没跑或请求失败返回 null。
  Future<int?> fetchConnectionCount() async {
    if (_phase != RuntimePhase.running) return null;
    final client = api;
    try {
      final body = await client.connections();
      final list = body['connections'];
      if (list is List) return list.length;
      return 0;
    } catch (_) {
      return null;
    } finally {
      client.close();
    }
  }

  /// 测一个节点的延迟（内核运行走接口，未运行走 TCP 探针）。
  Future<int?> testDelay(String name) async {
    final target = tcpTargetsFrom(configProvider())[name];
    final measured = await _measureOne(
      name,
      target: target,
      url: 'http://www.gstatic.com/generate_204',
      timeoutMs: 5000,
    );
    _delays = {..._delays, name: measured.value};
    final approx = {..._approxDelays};
    if (measured.approx) {
      approx.add(name);
    } else {
      approx.remove(name);
    }
    _approxDelays = approx;
    if (!_disposed) notifyListeners();
    return measured.value;
  }

  // -------------------------------------------------------------------- 内部

  /// 原子写 runtime.yaml.tpl（临时文件 + rename），与真实配置同目录。
  Future<void> _persistRuntimeTemplate(String yaml) async {
    final dir = _workDir;
    if (dir == null) return;
    try {
      final target = File('$dir/runtime.yaml.tpl');
      final tmp = File('${target.path}.tmp');
      await tmp.writeAsString(runtimeTemplateFrom(yaml), flush: true);
      await tmp.rename(target.path);
    } catch (_) {
      // 私有目录写失败极少见；下次启动会再试。
    }
  }

  String _buildRuntimeYaml(int fd) {
    return RuntimeConfig.buildRuntimeYaml(
      _activeConfig(),
      tunFileDescriptor: fd,
      controller: '127.0.0.1:$_controllerPort',
      secret: secret,
      tunStack: _startedTunStack,
      mixedPort: windowsKernel == null ? null : proxyPort,
    );
  }

  Future<String> _resolveWorkDir() async {
    final dir = await getApplicationSupportDirectory();
    final path = '${dir.path}/mihomo';
    await Directory(path).create(recursive: true);
    return path;
  }

  Future<void> _refreshRuntimeView() async {
    final client = api;
    try {
      final map = await client.proxyMap();
      final selected = <String, String>{};
      final members = <String, List<String>>{};
      map.forEach((name, info) {
        final all = info['all'];
        if (all is! List) return;
        members[name] = all.map((item) => '$item').toList(growable: false);
        final now = info['now'];
        if (now is String) selected[name] = now;
      });
      if (_disposed) return;
      _selected = selected;
      _members = members;
      notifyListeners();
      unawaited(_applySavedGlobalExit());
    } catch (_) {
      // 内核还没起来时忽略
    } finally {
      client.close();
    }
  }

  /// 内核起来后，把设置里保存的全局出口应用一次。
  ///
  /// 只在本次启动里生效：用户之后在运行页临时换节点，不该被反复覆盖。
  Future<void> _applySavedGlobalExit() async {
    if (_globalExitApplied) return;
    // 先置位再重放：中途 refresh 回到这里也不会套娃。
    _globalExitApplied = true;
    final settings = settingsProvider?.call();
    final saved = settings?.groupNodes ?? const <String, String>{};
    for (final entry in saved.entries) {
      final members = _members[entry.key];
      if (members == null || !members.contains(entry.value)) {
        // 组没了 / 节点已从组里移除：清掉这条记忆，下次启动不再重放。
        pruneSavedExit?.call(entry.key, null);
        continue;
      }
      if (_selected[entry.key] == entry.value) continue;
      await selectNode(entry.key, entry.value, quiet: true);
    }
    final node = settings?.globalNode;
    if (node == null || node.isEmpty) return;
    final globalMembers = _members['GLOBAL'];
    if (globalMembers == null || !globalMembers.contains(node)) {
      pruneSavedGlobalExit?.call();
      return;
    }
    if (_selected['GLOBAL'] == node) return;
    await selectNode('GLOBAL', node, quiet: true);
  }

  /// 内核启动成功后自动测一轮速（每次启动只测一次）。
  ///
  /// 失败/超时都只是把 [delays] 写成 null，不影响内核；
  /// 用户仍可随时手动「测速全部 / 测本组」。
  Future<void> _autoDelayOnce() async {
    if (_autoDelayed || _phase != RuntimePhase.running) return;
    _autoDelayed = true;
    final names = delayTargetsFrom(configProvider());
    if (names.isEmpty) return;
    await testDelays(names);
  }

  void _startPolling() {
    _stopPolling();
    // 先只轮询探活；等到内核真的应答了再订阅流量流，避免对还没起来的
    // 内核开一个注定失败的 HTTP 连接。
    _pollTimer = Timer.periodic(pollInterval, (_) => unawaited(_poll()));
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _trafficSub?.cancel();
    _trafficSub = null;
    _trafficClient?.close();
    _trafficClient = null;
  }

  Future<void> _poll() async {
    if (_disposed) return;
    if (windowsKernel != null) {
      if (_phase != RuntimePhase.running) return;
      if (_trafficSub == null) _subscribeTraffic();
      await _refreshRuntimeView();
      return;
    }
    final client = api;
    try {
      final alive = await client.ping();
      if (_disposed) return;
      if (!alive) {
        if (_phase == RuntimePhase.running) {
          _setError('内核无响应，可能已退出');
        } else {
          _setPhase(RuntimePhase.idle);
        }
      } else if (_phase != RuntimePhase.running) {
        _setPhase(RuntimePhase.running);
        if (_trafficSub == null) _subscribeTraffic();
        unawaited(_autoDelayOnce());
      } else {
        if (_trafficSub == null) _subscribeTraffic();
        await _refreshRuntimeView();
      }
    } finally {
      client.close();
    }
  }

  /// 订阅 `/traffic`。内核未就绪时这个流会立刻失败；异常必须就地吞掉，
  /// 否则 `async*` 生成器在订阅被取消后抛出的错误会变成未捕获的 zone 错误
  /// （测试里会直接判失败，真机上会污染 Flutter 的错误上报）。
  void _subscribeTraffic() {
    _trafficSub?.cancel();
    _trafficSub = null;
    final client = api;
    final Stream<({int up, int down})> stream;
    try {
      stream = client.traffic();
    } catch (_) {
      if (windowsKernel != null) client.close();
      return;
    }
    // 运行中的流要持有客户端，Windows 停止时一并关闭循环读取。
    if (windowsKernel != null) _trafficClient = client;
    void disconnected() {
      if (_trafficClient != client) return;
      _trafficClient = null;
      _trafficSub = null;
      _latestTraffic = null;
      client.close();
      if (!_disposed) notifyListeners();
    }

    _trafficSub = runZonedGuarded<StreamSubscription<({int up, int down})>>(
      () => stream.listen(
        (event) {
          if (_disposed) return;
          _up = event.up;
          _down = event.down;
          _latestTraffic = (at: DateTime.now(), up: _up, down: _down);
          notifyListeners();
        },
        onError: (Object _) => disconnected(),
        onDone: disconnected,
        cancelOnError: true,
      ),
      (Object _, StackTrace _) {
        // 内核没起来 / 已经退出：忽略流量流上的失败。
      },
    );
  }

  Future<Object?> _handleDartCall(MethodCall call) async {
    switch (call.method) {
      case 'buildRuntimeConfig':
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        final fd = (args['fd'] as num?)?.toInt() ?? 0;
        _lastFd = fd;
        _startedTunStack = fd > 0
            ? (args['tunStack'] as String?) ??
                  RuntimeConfig.tunStackFor(_activeConfig())
            : null;
        final yaml = _buildRuntimeYaml(fd);
        // 顺带落一份模板：Flutter 不在时（磁贴/小组件冷启动）Kotlin 用它
        // 替换 file-descriptor 后 spawn。写失败不影响本次启动。
        // 临时测速内核的配置只服务这一次测速，绝不能覆盖用户模板。
        if (!_tempConfigActive) {
          await _persistRuntimeTemplate(yaml);
        }
        return yaml;
      case 'onRuntimeState':
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        final state = args['state'] as String? ?? '';
        final message = args['message'] as String?;
        _pid = (args['pid'] as num?)?.toInt() ?? _pid;
        var reloadLogs = true;
        switch (state) {
          case 'starting':
            _setPhase(RuntimePhase.starting);
            break;
          case 'running':
            _serviceRunning = true;
            _setPhase(RuntimePhase.running);
            unawaited(_refreshRuntimeView());
            _startPolling();
            unawaited(_autoDelayOnce());
            break;
          case 'stopped':
            _stopPolling();
            _serviceRunning = false;
            // 停内核后概览不能还挂着上一次的 PID、速率和日志。
            _pid = null;
            _up = 0;
            _down = 0;
            _logs = const <String>[];
            reloadLogs = false;
            _setPhase(RuntimePhase.idle);
            break;
          case 'exited':
          case 'error':
            _stopPolling();
            _serviceRunning = false;
            _up = 0;
            _down = 0;
            if (message != null) _lastError = message;
            _setPhase(RuntimePhase.error);
            break;
        }
        if (reloadLogs) await loadLogs();
        break;
    }
    return null;
  }

  void _setPhase(RuntimePhase phase) {
    if (_disposed) return;
    final wasRunning = _phase == RuntimePhase.running;
    if (phase == RuntimePhase.running && !wasRunning) {
      _startedAt = DateTime.now();
    } else if (phase != RuntimePhase.running) {
      _startedAt = null;
    }
    _phase = phase;
    notifyListeners();
  }

  void _setError(String message) {
    if (_disposed) return;
    _lastError = message;
    _startedAt = null;
    _phase = RuntimePhase.error;
    notifyListeners();
  }
}
