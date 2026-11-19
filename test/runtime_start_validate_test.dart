import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';

/// 组成员不存在：mihomo 会 `proxy group ... not found` 直接退出。
const _bad = '''
proxy-groups:
  - name: G
    type: select
    proxies: [GHOST]
rules:
  - MATCH,G
''';

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

  const channelName = 'test/runtime-start';
  late List<MethodCall> calls;
  late Directory dir;
  RuntimeController? controller;

  setUp(() async {
    calls = [];
    dir = await Directory.systemTemp.createTemp('clashdeck_start_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          calls.add(call);
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

  RuntimeController make(String yaml) => RuntimeController(
    configProvider: () => YamlDoc.parse(yaml),
    channel: const MethodChannel(channelName),
    androidOverride: true,
    workDirProvider: () async => dir.path,
    pollInterval: const Duration(hours: 1),
  );

  test('校验有错误时不 spawn，并保存 issues', () async {
    controller = make(_bad);
    final started = await controller!.start();
    expect(started, isFalse);
    expect(calls, isEmpty);
    final report = controller!.startupReport;
    expect(report, isNotNull);
    expect(report!.hasErrors, isTrue);
    expect(report.issues.any((e) => e.code == 'dangling-member'), isTrue);
    expect(controller!.lastError, '配置无法启动：1 个错误');
    expect(controller!.phase, RuntimePhase.error);
  });

  test('确认「仍然启动」后绕过校验，仍发起 start', () async {
    controller = make(_bad);
    final started = await controller!.start(force: true);
    expect(started, isTrue);
    expect(calls.single.method, 'start');
    expect(controller!.startupReport, isNull);
  });

  test('合法配置直接启动，不显示校验错误', () async {
    controller = make(_valid);
    final started = await controller!.start();
    expect(started, isTrue);
    expect(controller!.startupReport, isNull);
    expect(controller!.lastError, isNull);
    expect(calls.single.method, 'start');
  });

  test('默认向 VpnService 传 ipv6=false', () async {
    controller = make(_valid);
    await controller!.start();
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['ipv6'], isFalse);
  });

  test('YAML 里 ipv6: true 时才传 true', () async {
    controller = make('$_valid\nipv6: true\n');
    await controller!.start();
    final args = calls.single.arguments as Map<Object?, Object?>;
    expect(args['ipv6'], isTrue);
  });
}
