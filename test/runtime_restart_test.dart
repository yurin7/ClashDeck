import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';

const _valid = '''
proxies:
  - {name: A, type: ss, server: 1.2.3.4, port: 8388, cipher: aes-128-gcm, password: pw}
proxy-groups:
  - name: G
    type: select
    proxies: [A]
rules:
  - MATCH,G
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'test/runtime-restart';
  late List<MethodCall> calls;
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
    dir = await Directory.systemTemp.createTemp('clashdeck_restart_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          calls.add(call);
          if (call.method == 'start') {
            // Kotlin 拿到 fd 后会回 running；测试里立刻模拟一下。
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
  );

  int count(String method) => calls.where((c) => c.method == method).length;

  test('运行中保存：合并后重启一次', () async {
    controller = make();
    expect(await controller!.start(), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 120));
    expect(controller!.phase, RuntimePhase.running);
    expect(count('start'), 1);

    await controller!.restartIfRunning(reason: '配置已保存');
    await Future<void>.delayed(const Duration(milliseconds: 1200));

    expect(count('stop'), 1);
    expect(count('start'), 2);
    expect(controller!.phase, RuntimePhase.running);
    expect(controller!.restarting, isFalse);
  });

  test('内核没运行：保存不触发任何通道调用', () async {
    controller = make();
    await controller!.restartIfRunning(reason: '配置已保存');
    await Future<void>.delayed(const Duration(milliseconds: 800));
    expect(calls, isEmpty);
    expect(controller!.phase, RuntimePhase.idle);
  });

  test('500ms 内连续保存：只重启一次', () async {
    controller = make();
    await controller!.start();
    await Future<void>.delayed(const Duration(milliseconds: 120));

    await controller!.restartIfRunning(reason: '第一次保存');
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await controller!.restartIfRunning(reason: '第二次保存');
    await Future<void>.delayed(const Duration(milliseconds: 1400));

    expect(count('stop'), 1);
    expect(count('start'), 2);
  });
}
