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
import 'runtime_config.dart';

/// 内核 + VPN 的生命周期阶段。
enum RuntimePhase { idle, starting, running, stopping, error }

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
  }) : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler(_handleDartCall);
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
  final int port;
  final String? secret;
  final Duration pollInterval;

  RuntimePhase _phase = RuntimePhase.idle;
  String? _lastError;
  ValidationReport? _startupReport;
  int? _pid;
  String? _workDir;
  int _lastFd = 0;
  List<String> _logs = const [];
  Map<String, String> _selected = const {};
  Map<String, List<String>> _members = const {};
  Map<String, int?> _delays = const {};

  /// 本次启动是否已经把设置里的全局出口应用过（只做一次）。
  bool _globalExitApplied = false;

  /// 规则集缓存缺失（补拉也失败）的个数，供 UI 提示「N 个规则集未生效」。
  int _missingRuleCaches = 0;
  int _up = 0;
  int _down = 0;

  /// VpnService 是否在运行（Kotlin 侧 `ClashVpnService.running`）。
  bool _serviceRunning = false;

  Timer? _pollTimer;

  /// 本次启动时间；内核未运行时为 null。
  DateTime? _startedAt;
  StreamSubscription<({int up, int down})>? _trafficSub;
  bool _disposed = false;

  RuntimePhase get phase => _phase;
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

  /// 本次启动时间；内核未运行时为 null。
  DateTime? get startedAt => _startedAt;

  int get up => _up;
  int get down => _down;

  /// 本次启动时补拉也失败的规则集缓存个数（UI 用来提示「N 个规则集未生效」）。
  int get missingRuleCaches => _missingRuleCaches;

  bool get isBusy =>
      _phase == RuntimePhase.starting || _phase == RuntimePhase.stopping;

  MihomoApi get api => MihomoApi(host: '127.0.0.1', port: port, secret: secret);

  // ------------------------------------------------------------------ 生命周期

  @override
  void dispose() {
    _disposed = true;
    _stopPolling();
    _channel.setMethodCallHandler(null);
    super.dispose();
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
  Future<bool> start({bool force = false}) async {
    if (!(androidOverride ?? supported)) {
      _setError('运行内核只支持 Android 设备');
      return false;
    }
    if (_phase == RuntimePhase.starting || _phase == RuntimePhase.running) {
      return true;
    }
    _lastError = null;
    _startupReport = null;
    _globalExitApplied = false;
    _setPhase(RuntimePhase.starting);
    try {
      // 先做语义自检：组成员/规则目标/规则集引用不存在时 mihomo 会直接退出，
      // 与其让用户看到「启动失败」再猜，不如在 spawn 前拦下并列出问题。
      final config = configProvider();
      if (!force) {
        final report = ConfigValidator.validate(config);
        if (report.hasErrors) {
          _startupReport = report;
          _setError('配置无法启动：${report.errors.length} 个错误');
          return false;
        }
      }
      _workDir ??= await (workDirProvider?.call() ?? _resolveWorkDir());
      // 先把 GEOIP/GEOSITE 数据铺进工作目录：内核缺数据会同步去 GitHub 下载，
      // 国内基本必定超时，带 GEOIP 规则的配置会直接启动失败。
      await Geodata.ensure(Directory(_workDir!));
      // 换机/清数据后 `type: file` 的规则集会找不到文件，这里先补一次；
      // 补不上也不阻塞启动，只把个数报给 UI。
      await _backfillRuleCaches();
      final settings = settingsProvider?.call() ?? AppSettings.defaults;
      final rawMtu = config.plainAt(['tun', 'mtu']);
      await _channel.invokeMethod<Map<Object?, Object?>>('start', {
        'workDir': _workDir,
        'port': port,
        'secret': secret,
        'mtu': rawMtu is num ? rawMtu.toInt() : 9000,
        // system / mixed 栈要在网卡上 bind 内核算出来的 tun 地址，这里把同一个
        // 地址交给 Kotlin 建网卡（gVisor 不看地址，但写了也无害）。
        'tunAddress': RuntimeConfig.tunAddressFor(config),
        // 只有 YAML 里 ipv6: true 才让 VpnService 加 v6 地址/路由，否则 v6
        // 流量会被吸进 tun 后丢弃，部分网络下表现为「连不上」。
        'ipv6': config.plainAt(['ipv6']) == true,
        ...settings.toStartArgs(),
      });
      // 系统授权对话框由 Activity 处理，结果通过 onRuntimeState 回来。
      return true;
    } catch (error) {
      _setError('启动失败：$error');
      return false;
    }
  }

  Future<void> stop() async {
    if (_phase == RuntimePhase.idle) return;
    _setPhase(RuntimePhase.stopping);
    try {
      await _channel.invokeMethod<void>('stop');
    } catch (error) {
      _setError('停止失败：$error');
    }
  }

  /// VpnService 是否在运行（Kotlin 侧 ClashVpnService.running）。
  ///
  /// 与 [phase] 不同：phase 看内核进程，serviceRunning 看 VPN 服务；
  /// 诊断面板用它区分「服务没起来」和「内核起来了但隧道没接管」。
  bool get serviceRunning => _serviceRunning;

  /// 从 Android 侧同步一次真实状态（进入页面时用）。
  Future<void> refreshStatus() async {
    if (!supported) return;
    try {
      final status = await _channel.invokeMethod<Map<Object?, Object?>>(
        'status',
      );
      if (status == null) {
        await loadLogs();
        return;
      }
      _pid = (status['pid'] as num?)?.toInt();
      final error = status['error'] as String?;
      _serviceRunning = status['running'] == true;
      // 以内核进程为准：即便服务的静态标记没更新，只要有 pid 就说明内核活着。
      final running =
          status['running'] == true || ((_pid ?? 0) > 0 && error == null);
      if (running) {
        _setPhase(RuntimePhase.running);
        unawaited(_refreshRuntimeView());
        _startPolling();
      } else if (error != null) {
        _lastError = error;
        _phase = RuntimePhase.error;
      } else if (_phase != RuntimePhase.starting) {
        _phase = RuntimePhase.idle;
      }
      await loadLogs();
      notifyListeners();
    } catch (_) {
      // 通道异常时保持现状。
    }
  }

  Future<List<String>> loadLogs({int limit = 300}) async {
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
  Future<bool> selectNode(String group, String node) async {
    final client = api;
    try {
      await client.selectProxy(group, node);
      _selected = {..._selected, group: node};
      notifyListeners();
      return true;
    } catch (error) {
      _setError('切换节点失败：$error');
      return false;
    } finally {
      client.close();
    }
  }

  /// 并发测一批节点的延迟，返回 节点名 → 毫秒（超时/失败为 null）。
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
    var next = 0;
    var done = 0;
    final limit = concurrency < 1 ? 1 : concurrency;
    Future<void> worker() async {
      while (true) {
        if (isCancelled?.call() ?? false) return;
        final index = next++;
        if (index >= total) return;
        final name = names[index];
        int? value;
        final client = api;
        try {
          value = await client.delay(name, url: url, timeoutMs: timeoutMs);
        } catch (_) {
          value = null;
        } finally {
          client.close();
        }
        results[name] = value;
        done += 1;
        _delays = {..._delays, name: value};
        if (!_disposed) notifyListeners();
        onProgress?.call(done, total);
      }
    }

    await Future.wait([for (var i = 0; i < limit && i < total; i++) worker()]);
    return results;
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

  /// 测一个节点的延迟。
  Future<int?> testDelay(String name) async {
    final client = api;
    try {
      final value = await client.delay(name);
      _delays = {..._delays, name: value};
      notifyListeners();
      return value;
    } catch (error) {
      _setError('测速失败：$error');
      return null;
    } finally {
      client.close();
    }
  }

  // -------------------------------------------------------------------- 内部

  String _buildRuntimeYaml(int fd) {
    return RuntimeConfig.buildRuntimeYaml(
      configProvider(),
      tunFileDescriptor: fd,
      controller: '127.0.0.1:$port',
      secret: secret,
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
    // 先把每个组切到记住的节点，再把 GLOBAL 切过去：顺序对了，用户看到的
    // 「GLOBAL → 组 → 组内节点」才和上次退出时一致。
    final saved =
        settingsProvider?.call().groupNodes ?? const <String, String>{};
    for (final entry in saved.entries) {
      if (_selected[entry.key] == entry.value) continue;
      await selectNode(entry.key, entry.value);
    }
    final node = settingsProvider?.call().globalNode;
    if (node == null || node.isEmpty) {
      _globalExitApplied = true;
      return;
    }
    if (_selected['GLOBAL'] == node) {
      _globalExitApplied = true;
      return;
    }
    if (await selectNode('GLOBAL', node)) _globalExitApplied = true;
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
  }

  Future<void> _poll() async {
    if (_disposed) return;
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
    final Stream<({int up, int down})> stream;
    try {
      stream = api.traffic();
    } catch (_) {
      return;
    }
    _trafficSub = runZonedGuarded<StreamSubscription<({int up, int down})>>(
      () => stream.listen(
        (event) {
          if (_disposed) return;
          _up = event.up;
          _down = event.down;
          notifyListeners();
        },
        onError: (Object _) {},
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
        return _buildRuntimeYaml(fd);
      case 'onRuntimeState':
        final args = (call.arguments as Map<Object?, Object?>?) ?? const {};
        final state = args['state'] as String? ?? '';
        final message = args['message'] as String?;
        _pid = (args['pid'] as num?)?.toInt() ?? _pid;
        switch (state) {
          case 'starting':
            _setPhase(RuntimePhase.starting);
            break;
          case 'running':
            _serviceRunning = true;
            _setPhase(RuntimePhase.running);
            unawaited(_refreshRuntimeView());
            _startPolling();
            break;
          case 'stopped':
            _stopPolling();
            _serviceRunning = false;
            _setPhase(RuntimePhase.idle);
            break;
          case 'exited':
          case 'error':
            _stopPolling();
            _serviceRunning = false;
            if (message != null) _lastError = message;
            _setPhase(RuntimePhase.error);
            break;
        }
        await loadLogs();
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
