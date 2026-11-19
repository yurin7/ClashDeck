import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';

const _valid = '''
proxies:
  - {name: A, type: ss, server: 1.2.3.4, port: 8388, cipher: aes-128-gcm, password: pw}
  - {name: B, type: ss, server: 5.6.7.8, port: 8388, cipher: aes-128-gcm, password: pw}
proxy-groups:
  - name: G
    type: select
    proxies: [A, B]
rules:
  - MATCH,G
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'test/runtime-delay';
  late List<MethodCall> calls;
  late List<String> probed;
  late Directory dir;
  RuntimeController? controller;

  Future<void> feedState(String state, {int? pid}) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall('onRuntimeState', {'state': state, 'pid': pid}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channelName, data, (_) {});
  }

  setUp(() async {
    calls = [];
    probed = [];
    dir = await Directory.systemTemp.createTemp('clashdeck_delay_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'start') {
            Future<void>.delayed(
              const Duration(milliseconds: 20),
              () => feedState('running', pid: 100),
            );
          } else if (call.method == 'stop') {
            Future<void>.delayed(
              const Duration(milliseconds: 20),
              () => feedState('stopped'),
            );
          }
          return null;
        });
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), null);
    await dir.delete(recursive: true);
  });

  RuntimeController make() => RuntimeController(
    configProvider: () => YamlDoc.parse(_valid),
    channel: const MethodChannel(channelName),
    androidOverride: true,
    workDirProvider: () async => dir.path,
    pollInterval: const Duration(hours: 1),
    delayProbe: (name) async {
      probed.add(name);
      return name == 'A' ? 42 : null;
    },
  );

  test('启动成功后自动测一轮，只测一次', () async {
    controller = make();
    expect(await controller!.start(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));

    expect(probed, ['A', 'B']);
    expect(controller!.delays['A'], 42);
    expect(controller!.delays['B'], isNull);
    expect(calls.where((c) => c.method == 'stop'), isEmpty);

    // 再收到一次 running 不应该重复测。
    await feedState('running', pid: 100);
    await Future<void>.delayed(const Duration(milliseconds: 60));
    expect(probed, ['A', 'B']);
  });

  test('手动测速仍然可用，进行中标记为 true', () async {
    controller = make();
    expect(await controller!.start(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    probed.clear();

    final future = controller!.testDelays(['A']);
    expect(controller!.delayTesting, isTrue);
    await future;
    expect(controller!.delayTesting, isFalse);
    expect(probed, ['A']);
  });

  test('停止后重新启动会再自动测一次', () async {
    controller = make();
    expect(await controller!.start(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(probed, ['A', 'B']);

    await controller!.stop();
    await Future<void>.delayed(const Duration(milliseconds: 80));
    probed.clear();

    expect(await controller!.start(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(probed, ['A', 'B']);
  });
}
