import 'dart:io';

import 'package:clashdeck/data/app_prefs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 测速缓存：写入后重新加载仍在；超时用 null 表示，不与 0ms 混淆。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clashdeck_prefs_latency');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.contains('ApplicationSupport')) return tmp.path;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Windows 上偶发文件仍被占用：测试结束清不掉临时目录不影响结论。
    }
  });

  testWidgets('测速结果按配置分开保存，超时记为 null', (tester) async {
    await tester.runAsync(() async {
      final prefs = await AppPrefs.load();
      await prefs.setLatencies('demo', {
        'HK-01': 120,
        'JP-01': null,
      }, at: DateTime(2026, 11, 19, 1, 2));
    });

    late AppPrefs reloaded;
    await tester.runAsync(() async {
      reloaded = await AppPrefs.load();
    });

    expect(reloaded.latenciesOf('demo'), {'HK-01': 120, 'JP-01': null});
    expect(reloaded.lastLatencyAt('demo'), DateTime(2026, 11, 19, 1, 2));
    expect(reloaded.latenciesOf('other'), isEmpty);
  });
}
