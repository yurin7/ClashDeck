import 'dart:io';

import 'package:clashdeck/data/app_prefs.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 检查更新的全局偏好：默认关闭，写入后重新加载仍在。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clashdeck_prefs_update');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.contains('ApplicationSupport')) return tmp.path;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    await tmp.delete(recursive: true);
  });

  testWidgets('默认关闭，且不触发任何网络检查', (tester) async {
    late AppPrefs prefs;
    await tester.runAsync(() async {
      prefs = await AppPrefs.load();
    });
    expect(prefs.updateAutoCheck, isFalse);
    expect(prefs.lastUpdateCheckAt, isNull);
    expect(prefs.lastNotifiedVersion, isNull);
    // 规则自动更新是另一个开关，默认仍为开，别被这次改动带偏。
    expect(prefs.ruleAutoUpdate, isTrue);
  });

  testWidgets('开关 / 上次检查时间 / 已提示版本可持久化', (tester) async {
    await tester.runAsync(() async {
      final prefs = await AppPrefs.load();
      await prefs.setUpdateAutoCheck(true);
      await prefs.setLastUpdateCheckAt(DateTime(2026, 11, 19, 1, 2));
      await prefs.setLastNotifiedVersion('0.2.2');
    });

    late AppPrefs reloaded;
    await tester.runAsync(() async {
      reloaded = await AppPrefs.load();
    });
    expect(reloaded.updateAutoCheck, isTrue);
    expect(reloaded.lastUpdateCheckAt, DateTime(2026, 11, 19, 1, 2));
    expect(reloaded.lastNotifiedVersion, '0.2.2');
  });
}
