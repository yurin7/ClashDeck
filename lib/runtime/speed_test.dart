import 'dart:async';
import 'dart:io';

/// 节点下载测速：纯 Dart（不依赖 Flutter），下载器与会话状态机都可注入。
///
/// 会话做的事：
/// 1. 内核没跑 → 调用方注入的 `startTemporary()`（仅端口模式，不申请 VPN）；
/// 2. 等内核 API 就绪 → 取本地代理端口；
/// 3. 让调用方把某个 selector 切到目标节点（`prepareProxy`）；
/// 4. 经本地代理端口下载测速文件；
/// 5. 无论成功失败都恢复 selector；如果内核是本次临时启动的，关掉它。// 测速线路。只影响下载 URL，速度计算与截断逻辑完全一致。
enum SpeedSource { fast, google, github, custom }

/// 线路 + 自定义地址（自定义地址只在 [source] 为 custom 时生效）。
class SpeedSourceChoice {
  const SpeedSourceChoice(this.source, [this.customUrl = '']);

  static const defaultChoice = SpeedSourceChoice(SpeedSource.fast);

  final SpeedSource source;
  final String customUrl;

  String get label => switch (source) {
    SpeedSource.fast => 'Fast',
    SpeedSource.google => 'Google',
    SpeedSource.github => 'GitHub',
    SpeedSource.custom => '自定义',
  };

  /// 自定义地址是否合法（仅 http/https + 无空白）。
  bool get hasValidCustomUrl => _customUrlPattern.hasMatch(customUrl.trim());

  /// 实际要下载的地址；自定义线路非法时返回 null。
  Uri? get url => switch (source) {
    SpeedSource.fast => Uri.parse(_fastUrl),
    SpeedSource.google => Uri.parse(_googleUrl),
    SpeedSource.github => Uri.parse(_githubUrl),
    SpeedSource.custom =>
      hasValidCustomUrl ? Uri.tryParse(customUrl.trim()) : null,
  };

  SpeedSourceChoice withSource(SpeedSource value) =>
      SpeedSourceChoice(value, customUrl);

  SpeedSourceChoice withCustomUrl(String value) =>
      SpeedSourceChoice(SpeedSource.custom, value);
}

const String _fastUrl = 'https://speed.cloudflare.com/__down?bytes=26214400';
const String _googleUrl =
    'https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb';
const String _githubUrl =
    'https://github.com/microsoft/vscode/archive/refs/tags/1.85.0.zip';

final RegExp _customUrlPattern = RegExp(r'^https?://[^\s]+$');

/// 单次下载测速的结果。
class SpeedTestResult {
  const SpeedTestResult({
    required this.ok,
    this.bytes = 0,
    this.elapsed = Duration.zero,
    this.failure,
    this.cancelled = false,
  });

  factory SpeedTestResult.failed(String reason, {bool cancelled = false}) =>
      SpeedTestResult(ok: false, failure: reason, cancelled: cancelled);

  final bool ok;
  final int bytes;
  final Duration elapsed;

  /// 失败原因（中文，直接给 UI）。
  final String? failure;
  final bool cancelled;

  /// 兆字节每秒（按 1024² 计算，与系统「MB/s」一致）。
  double get megabytesPerSecond {
    final micros = elapsed.inMicroseconds;
    if (bytes <= 0 || micros <= 0) return 0;
    return bytes / (1024 * 1024) / (micros / 1000000);
  }

  /// 结果行：`12.3 MB/s · 25 MB / 8.4s`。
  String get summary {
    final mb = bytes / (1024 * 1024);
    final seconds = elapsed.inMilliseconds / 1000;
    return '${megabytesPerSecond.toStringAsFixed(1)} MB/s · '
        '${mb.toStringAsFixed(mb >= 10 ? 0 : 1)} MB / '
        '${seconds.toStringAsFixed(1)}s';
  }
}

/// 下载过程中的实时进度（节流后回调）。
class SpeedTestProgress {
  const SpeedTestProgress({
    required this.bytes,
    required this.elapsed,
    required this.megabytesPerSecond,
  });

  final int bytes;
  final Duration elapsed;
  final double megabytesPerSecond;
}

/// 协作式取消令牌：下载循环每个分片检查一次。
class SpeedTestCancelToken {
  bool _cancelled = false;

  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

/// 测速文件上限：25MB。
const int kSpeedTestMaxBytes = 25 * 1024 * 1024;

/// 单次下载最长 10 秒。
const Duration kSpeedTestMaxDuration = Duration(seconds: 10);

/// 连接超时 4 秒。
const Duration kSpeedTestConnectTimeout = Duration(seconds: 4);

/// 会话失败原因（直接展示）。
class SpeedTestFailure implements Exception {
  const SpeedTestFailure(this.message);

  final String message;

  @override
  String toString() => message;
}

typedef SpeedHttpClientFactory = HttpClient Function();

/// 下载器：经本地代理端口拉取测速文件，边读边统计，到上限立即断开。
class SpeedDownloader {
  SpeedDownloader({SpeedHttpClientFactory? clientFactory})
    : _clientFactory = clientFactory ?? HttpClient.new;

  final SpeedHttpClientFactory _clientFactory;

  /// [proxy] 形如 `127.0.0.1:7890`；为空表示直连（测试用）。
  Future<SpeedTestResult> download(
    Uri url, {
    String? proxy,
    int maxBytes = kSpeedTestMaxBytes,
    Duration maxDuration = kSpeedTestMaxDuration,
    void Function(SpeedTestProgress)? onProgress,
    SpeedTestCancelToken? cancelToken,
  }) async {
    final client = _clientFactory();
    final stopwatch = Stopwatch()..start();
    var bytes = 0;
    var lastReportAt = 0;
    try {
      client.connectionTimeout = kSpeedTestConnectTimeout;
      client.autoUncompress = false;
      if (proxy != null && proxy.isNotEmpty) {
        client.findProxy = (_) => 'PROXY $proxy';
      }
      final request = await client
          .getUrl(url)
          .timeout(kSpeedTestConnectTimeout);
      request.followRedirects = true;
      final response = await request.close();
      if (response.statusCode != HttpStatus.ok) {
        return SpeedTestResult.failed('HTTP ${response.statusCode}');
      }
      await for (final chunk in response) {
        if (cancelToken?.isCancelled ?? false) {
          return SpeedTestResult.failed('已取消', cancelled: true);
        }
        bytes += chunk.length;
        final elapsed = stopwatch.elapsed;
        final milliseconds = elapsed.inMilliseconds;
        if (milliseconds - lastReportAt >= 200) {
          lastReportAt = milliseconds;
          onProgress?.call(
            SpeedTestProgress(
              bytes: bytes,
              elapsed: elapsed,
              megabytesPerSecond: _mbps(bytes, elapsed),
            ),
          );
        }
        if (bytes >= maxBytes || elapsed >= maxDuration) break;
      }
      final elapsed = stopwatch.elapsed;
      if (bytes <= 0) {
        return SpeedTestResult.failed('没有收到数据');
      }
      return SpeedTestResult(
        ok: true,
        bytes: bytes > maxBytes ? maxBytes : bytes,
        elapsed: elapsed,
      );
    } on TimeoutException {
      return SpeedTestResult.failed('连接超时');
    } on SocketException catch (error) {
      final reason = (error.osError?.message ?? error.message).trim();
      return SpeedTestResult.failed(
        reason.isEmpty ? '代理连接失败' : '代理连接失败：$reason',
      );
    } on HttpException catch (error) {
      return SpeedTestResult.failed('下载中断：${error.message}');
    } catch (error) {
      return SpeedTestResult.failed('测速失败：$error');
    } finally {
      client.close(force: true);
    }
  }

  static double _mbps(int bytes, Duration elapsed) {
    final micros = elapsed.inMicroseconds;
    if (micros <= 0) return 0;
    return bytes / (1024 * 1024) / (micros / 1000000);
  }
}

/// 会话阶段，UI 用来显示提示。
enum SpeedTestStage {
  idle,

  /// 正在临时启动仅端口内核。
  starting,

  /// 等待内核 API/代理口就绪。
  waiting,

  /// 正在下载。
  downloading,

  /// 正在恢复选择/关闭临时内核。
  restoring,
}

/// 会话状态机：把「临时启动 → 切 selector → 下载 → 恢复/关闭」串起来。
///
/// 所有副作用都通过构造参数注入，单测里可以全 fake。
class SpeedTestSession {
  SpeedTestSession({
    required this.downloader,
    required this.kernelReady,
    required this.startTemporary,
    required this.stopTemporary,
    required this.proxyPort,
    required this.prepareProxy,
    required this.restoreProxy,
    this.readyTimeout = const Duration(seconds: 15),
  });

  final SpeedDownloader downloader;

  /// 内核是否已经在运行（running/starting 都算「用户本来就有」）。
  final bool Function() kernelReady;
  final Future<bool> Function() startTemporary;
  final Future<void> Function() stopTemporary;
  final Future<int?> Function() proxyPort;

  /// 把 selector 指向 [node]；false 表示该节点不在任何可选组里。
  final Future<bool> Function(String node) prepareProxy;
  final Future<void> Function() restoreProxy;
  final Duration readyTimeout;

  Future<SpeedTestResult> run(
    String node, {
    required Uri url,
    void Function(SpeedTestProgress)? onProgress,
    void Function(SpeedTestStage)? onStage,
    SpeedTestCancelToken? cancelToken,
  }) async {
    final wasRunning = kernelReady();
    var startedHere = false;
    try {
      if (!wasRunning) {
        onStage?.call(SpeedTestStage.starting);
        startedHere = await startTemporary();
        if (!startedHere) {
          return SpeedTestResult.failed('临时启动内核失败');
        }
      }
      onStage?.call(SpeedTestStage.waiting);
      final port = await _waitProxyPort();
      if (port == null) {
        return SpeedTestResult.failed('代理端口未就绪');
      }
      if (!await prepareProxy(node)) {
        return SpeedTestResult.failed('该节点不在任何可选组里');
      }
      onStage?.call(SpeedTestStage.downloading);
      return await downloader.download(
        url,
        proxy: '127.0.0.1:$port',
        onProgress: onProgress,
        cancelToken: cancelToken,
      );
    } finally {
      onStage?.call(SpeedTestStage.restoring);
      await restoreProxy();
      if (startedHere) {
        await stopTemporary();
      }
      onStage?.call(SpeedTestStage.idle);
    }
  }

  Future<int?> _waitProxyPort() async {
    final deadline = DateTime.now().add(readyTimeout);
    while (DateTime.now().isBefore(deadline)) {
      final port = await proxyPort();
      if (port != null && port > 0) return port;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return null;
  }
}
