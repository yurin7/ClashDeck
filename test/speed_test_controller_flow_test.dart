import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:clashdeck/runtime/speed_test.dart';

const _docText = r'''
mixed-port: 7890
proxies:
  - {name: alpha, type: ss, server: 1.2.3.4, port: 443, cipher: aes-128-gcm, password: pw}
rules:
  - MATCH,DIRECT
''';

class _FakeDownloader extends SpeedDownloader {
  int calls = 0;
  String? proxySeen;

  @override
  Future<SpeedTestResult> download(
    Uri url, {
    String? proxy,
    int maxBytes = kSpeedTestMaxBytes,
    Duration maxDuration = kSpeedTestMaxDuration,
    void Function(SpeedTestProgress progress)? onProgress,
    SpeedTestCancelToken? cancelToken,
  }) async {
    calls++;
    proxySeen = proxy;
    return const SpeedTestResult(
      ok: true,
      bytes: 1024 * 1024,
      elapsed: Duration(milliseconds: 500),
    );
  }
}

class _FakeRuntime extends RuntimeController {
  _FakeRuntime(YamlDoc Function() doc)
    : super(
        configProvider: doc,
        androidOverride: true,
        pollInterval: const Duration(milliseconds: 10),
      );

  final List<String> calls = <String>[];

  @override
  Future<bool> start({bool force = false, String? proxyModeOverride}) async {
    calls.add('start:${proxyModeOverride ?? 'tun'}');
    debugSetPhase(RuntimePhase.running);
    return true;
  }

  @override
  Future<void> stop() async {
    calls.add('stop');
    debugSetPhase(RuntimePhase.idle);
  }

  @override
  int get proxyPort => 7891;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('内核原本未运行：临时启动仅端口内核，测完关闭', () async {
    final runtime = _FakeRuntime(() => YamlDoc.parse(_docText));
    final downloader = _FakeDownloader();

    final result = await runtime.runSpeedTest('alpha', downloader: downloader);

    expect(result.ok, isTrue);
    expect(downloader.proxySeen, '127.0.0.1:7891');
    expect(runtime.calls, ['start:port', 'stop']);
    expect(runtime.phase, RuntimePhase.idle);
  });

  test('内核原本在运行：先停、临时启动、测完停掉并按原配置重启', () async {
    final runtime = _FakeRuntime(() => YamlDoc.parse(_docText));
    runtime.debugSetPhase(RuntimePhase.running);
    final downloader = _FakeDownloader();

    final result = await runtime.runSpeedTest('alpha', downloader: downloader);

    expect(result.ok, isTrue);
    expect(runtime.calls, ['stop', 'start:port', 'stop', 'start:tun']);
    expect(runtime.phase, RuntimePhase.running);
  });

  test('找不到节点时不启动任何内核，直接返回中文原因', () async {
    final runtime = _FakeRuntime(() => YamlDoc.parse(_docText));

    final result = await runtime.runSpeedTest('missing');

    expect(result.ok, isFalse);
    expect(result.failure, '找不到节点：missing');
    expect(runtime.calls, isEmpty);
  });

  test('自定义地址不合法时直接失败', () async {
    final runtime = _FakeRuntime(() => YamlDoc.parse(_docText));

    final result = await runtime.runSpeedTest(
      'alpha',
      source: const SpeedSourceChoice(SpeedSource.custom, 'not-a-url'),
    );

    expect(result.ok, isFalse);
    expect(result.failure, '自定义地址不合法');
    expect(runtime.calls, isEmpty);
  });
}
