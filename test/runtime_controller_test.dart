import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';

const _sample = '''
# 用户配置，注释要保留
mixed-port: 7890
proxies:
  - name: A
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - A
rules:
  - MATCH,PROXY
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const codec = StandardMethodCodec();
  const channelName = 'test/runtime';

  /// 模拟 Android 侧反向调用 Dart。
  Future<Object?> callFromNative(MethodCall call) async {
    Object? reply;
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channelName, codec.encodeMethodCall(call), (
          data,
        ) {
          reply = data == null ? null : codec.decodeEnvelope(data);
        });
    return reply;
  }

  group('RuntimeController 与 Android 的契约', () {
    late RuntimeController controller;

    setUp(() {
      controller = RuntimeController(
        configProvider: () => YamlDoc.parse(_sample),
        channel: const MethodChannel(channelName),
        secret: 'tok',
        pollInterval: const Duration(hours: 1),
      );
    });

    tearDown(() {
      controller.dispose();
    });

    test('buildRuntimeConfig 用真实 fd 生成运行配置', () async {
      final reply = await callFromNative(
        const MethodCall('buildRuntimeConfig', {
          'fd': 7,
          'port': 9090,
          'secret': 'tok',
        }),
      );
      expect(reply, isA<String>());
      final yaml = reply! as String;
      final doc = YamlDoc.parse(yaml);
      expect(doc.isValid, isTrue);
      final root = doc.plainRoot;
      expect(root['external-controller'], '127.0.0.1:9090');
      expect(root['secret'], 'tok');
      final tun = root['tun'] as Map<String, Object?>;
      expect(tun['file-descriptor'], 7);
      expect(tun['enable'], isTrue);
      expect(tun['stack'], 'gvisor');
      expect((root['dns'] as Map<String, Object?>)['enhanced-mode'], 'fake-ip');
      expect(yaml.contains('# 用户配置，注释要保留'), isTrue);
    });

    test('onRuntimeState starting → running 会刷新阶段', () async {
      await callFromNative(
        const MethodCall('onRuntimeState', {'state': 'starting'}),
      );
      expect(controller.phase, RuntimePhase.starting);

      // running 会开始轮询（回环 9090 上没有内核，ping 会失败并被吞掉）。
      await callFromNative(
        const MethodCall('onRuntimeState', {'state': 'running', 'pid': 1234}),
      );
      expect(controller.phase, RuntimePhase.running);
      expect(controller.pid, 1234);
    });

    test('内核退出会把阶段置为 error 并带原因', () async {
      await callFromNative(
        const MethodCall('onRuntimeState', {
          'state': 'exited',
          'message': '内核退出（code=2）',
        }),
      );
      expect(controller.phase, RuntimePhase.error);
      expect(controller.lastError, contains('code=2'));
    });

    test('停止状态回到 idle', () async {
      await callFromNative(
        const MethodCall('onRuntimeState', {'state': 'running'}),
      );
      await callFromNative(
        const MethodCall('onRuntimeState', {'state': 'stopped'}),
      );
      expect(controller.phase, RuntimePhase.idle);
    });

    test('非 Android 平台 start 直接报错而不碰通道', () async {
      expect(RuntimeController.supported, isFalse);
      await controller.start();
      expect(controller.phase, RuntimePhase.error);
      expect(controller.lastError, contains('Android'));
    });

    test('refreshStatus 在通道不可用时静默失败', () async {
      await expectLater(controller.refreshStatus(), completes);
    });
  });
}
