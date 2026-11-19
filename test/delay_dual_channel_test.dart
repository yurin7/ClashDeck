import 'dart:io';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/delay_targets.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _yaml = '''
proxies:
  - {name: A, type: ss, server: 10.0.0.1, port: 8388, cipher: aes-128-gcm, password: pw}
  - {name: BROKEN, type: ss, cipher: aes-128-gcm, password: pw}
proxy-groups:
  - name: PROXY
    type: select
    proxies: [A]
rules:
  - MATCH,PROXY
''';

class _FakeSocket extends Fake implements Socket {
  @override
  void destroy() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'test/dual-channel';

  test('通道判定：running 与 starting 走内核，其它走 TCP', () {
    expect(RuntimeController.kernelDelayChannel(RuntimePhase.running), isTrue);
    expect(RuntimeController.kernelDelayChannel(RuntimePhase.starting), isTrue);
    for (final phase in [
      RuntimePhase.idle,
      RuntimePhase.stopping,
      RuntimePhase.error,
    ]) {
      expect(RuntimeController.kernelDelayChannel(phase), isFalse);
    }
  });

  test('canTestDelay 只在有节点且未在测速时为 true', () {
    expect(canTestDelay(hasNodes: true, testing: false), isTrue);
    expect(canTestDelay(hasNodes: true, testing: true), isFalse);
    expect(canTestDelay(hasNodes: false, testing: false), isFalse);
  });

  test('内核未运行：走 TCP 探针，结果标记为近似值', () async {
    var socketCount = 0;
    Future<Socket> connector(String host, int port, {Duration? timeout}) async {
      expect(host, '10.0.0.1');
      expect(port, 8388);
      socketCount += 1;
      return _FakeSocket();
    }

    final runtime = RuntimeController(
      configProvider: () => YamlDoc.parse(_yaml),
      channel: const MethodChannel(channelName),
      androidOverride: true,
      tcpConnector: connector,
    );
    addTearDown(runtime.dispose);

    final results = await runtime.testDelays(['A']);
    expect(results['A'], isNotNull);
    expect(runtime.delayApprox('A'), isTrue);
    expect(runtime.approxDelays, contains('A'));
    expect(socketCount, 1);

    // 单节点入口同样可用。
    final single = await runtime.testDelay('A');
    expect(single, isNotNull);
    expect(runtime.delayApprox('A'), isTrue);
  });

  test('没有 server/port 的节点不发探测，结果为空', () async {
    var called = false;
    final runtime = RuntimeController(
      configProvider: () => YamlDoc.parse(_yaml),
      channel: const MethodChannel(channelName),
      androidOverride: true,
      tcpConnector: (host, port, {timeout}) async {
        called = true;
        return _FakeSocket();
      },
    );
    addTearDown(runtime.dispose);

    final results = await runtime.testDelays(['BROKEN']);
    expect(results['BROKEN'], isNull);
    expect(runtime.delayApprox('BROKEN'), isFalse);
    expect(called, isFalse);
  });

  test('注入 delayProbe 时优先走注入值，且不标记近似', () async {
    final runtime = RuntimeController(
      configProvider: () => YamlDoc.parse(_yaml),
      channel: const MethodChannel(channelName),
      androidOverride: true,
      delayProbe: (_) async => 88,
      tcpConnector: (host, port, {timeout}) async => _FakeSocket(),
    );
    addTearDown(runtime.dispose);

    final results = await runtime.testDelays(['A']);
    expect(results['A'], 88);
    expect(runtime.delayApprox('A'), isFalse);
  });

  test('未启动内核时测速不触发 VPN/运行时通道调用', () async {
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (call) {
          calls.add(call.method);
          return null;
        });
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(const MethodChannel(channelName), null),
    );

    final runtime = RuntimeController(
      configProvider: () => YamlDoc.parse(_yaml),
      channel: const MethodChannel(channelName),
      androidOverride: true,
      tcpConnector: (host, port, {timeout}) async => _FakeSocket(),
    );
    addTearDown(runtime.dispose);

    await runtime.testDelays(['A', 'BROKEN']);
    expect(calls, isEmpty);
  });
}
