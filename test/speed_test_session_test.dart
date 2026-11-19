import 'package:flutter_test/flutter_test.dart';
import 'package:clashdeck/runtime/speed_test.dart';

class _StubDownloader extends SpeedDownloader {
  _StubDownloader({this.onCall});

  final void Function(Uri url, String? proxy, SpeedTestCancelToken? token)?
  onCall;

  int calls = 0;

  @override
  Future<SpeedTestResult> download(
    Uri url, {
    String? proxy,
    int maxBytes = kSpeedTestMaxBytes,
    Duration maxDuration = kSpeedTestMaxDuration,
    void Function(SpeedTestProgress progress)? onProgress,
    SpeedTestCancelToken? cancelToken,
  }) async {
    calls += 1;
    onCall?.call(url, proxy, cancelToken);
    return const SpeedTestResult(
      ok: true,
      bytes: 1024,
      elapsed: Duration(seconds: 1),
    );
  }
}

void main() {
  test('内核未运行：临时启动 → 下载 → 恢复选择 → 关闭临时内核', () async {
    var started = 0;
    var stopped = 0;
    var restored = 0;
    final stages = <SpeedTestStage>[];
    final downloader = _StubDownloader();
    final session = SpeedTestSession(
      downloader: downloader,
      kernelReady: () => false,
      startTemporary: () async {
        started += 1;
        return true;
      },
      stopTemporary: () async => stopped += 1,
      proxyPort: () async => 7890,
      prepareProxy: (_) async => true,
      restoreProxy: () async => restored += 1,
    );

    final result = await session.run(
      '日本 01',
      url: Uri.parse('https://speed.test/file'),
      onStage: stages.add,
    );

    expect(result.ok, isTrue);
    expect(started, 1);
    expect(stopped, 1);
    expect(restored, 1);
    expect(stages, contains(SpeedTestStage.starting));
    expect(stages, contains(SpeedTestStage.downloading));
    expect(stages.last, SpeedTestStage.idle);
    expect(downloader.calls, 1);
  });

  test('内核已在运行：不重启、不关闭，只切选择并在结束后恢复', () async {
    var started = 0;
    var stopped = 0;
    var restored = 0;
    final session = SpeedTestSession(
      downloader: _StubDownloader(),
      kernelReady: () => true,
      startTemporary: () async {
        started += 1;
        return true;
      },
      stopTemporary: () async => stopped += 1,
      proxyPort: () async => 7890,
      prepareProxy: (_) async => true,
      restoreProxy: () async => restored += 1,
    );
    final result = await session.run(
      'HK',
      url: Uri.parse('https://speed.test/file'),
    );
    expect(result.ok, isTrue);
    expect(started, 0);
    expect(stopped, 0);
    expect(restored, 1);
  });

  test('节点不在可选组：失败、仍恢复并关闭临时内核', () async {
    var stopped = 0;
    var restored = 0;
    final session = SpeedTestSession(
      downloader: _StubDownloader(),
      kernelReady: () => false,
      startTemporary: () async => true,
      stopTemporary: () async => stopped += 1,
      proxyPort: () async => 7890,
      prepareProxy: (_) async => false,
      restoreProxy: () async => restored += 1,
    );
    final result = await session.run(
      'X',
      url: Uri.parse('https://speed.test/file'),
    );
    expect(result.ok, isFalse);
    expect(result.failure, '该节点不在任何可选组里');
    expect(restored, 1);
    expect(stopped, 1);
  });

  test('代理端口未就绪：失败提示明确，且不发起下载', () async {
    final downloader = _StubDownloader();
    final session = SpeedTestSession(
      downloader: downloader,
      kernelReady: () => true,
      startTemporary: () async => true,
      stopTemporary: () async {},
      proxyPort: () async => null,
      prepareProxy: (_) async => true,
      restoreProxy: () async {},
      readyTimeout: const Duration(milliseconds: 200),
    );
    final result = await session.run(
      'X',
      url: Uri.parse('https://speed.test/file'),
    );
    expect(result.ok, isFalse);
    expect(result.failure, '代理端口未就绪');
    expect(downloader.calls, 0);
  });

  test('下载走 127.0.0.1:端口，取消令牌原样传入', () async {
    SpeedTestCancelToken? seen;
    String? proxy;
    final downloader = _StubDownloader(
      onCall: (url, value, token) {
        proxy = value;
        seen = token;
      },
    );
    final token = SpeedTestCancelToken();
    final session = SpeedTestSession(
      downloader: downloader,
      kernelReady: () => true,
      startTemporary: () async => true,
      stopTemporary: () async {},
      proxyPort: () async => 7891,
      prepareProxy: (_) async => true,
      restoreProxy: () async {},
    );
    await session.run(
      'X',
      url: Uri.parse('https://speed.test/file'),
      cancelToken: token,
    );
    expect(proxy, '127.0.0.1:7891');
    expect(seen, same(token));
  });

  test('临时启动失败：提示失败且不下载', () async {
    final downloader = _StubDownloader();
    final session = SpeedTestSession(
      downloader: downloader,
      kernelReady: () => false,
      startTemporary: () async => false,
      stopTemporary: () async {},
      proxyPort: () async => 7890,
      prepareProxy: (_) async => true,
      restoreProxy: () async {},
    );
    final result = await session.run(
      'X',
      url: Uri.parse('https://speed.test/file'),
    );
    expect(result.ok, isFalse);
    expect(result.failure, '临时启动内核失败');
    expect(downloader.calls, 0);
  });
}
