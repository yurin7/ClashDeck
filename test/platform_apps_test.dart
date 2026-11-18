import 'package:clashdeck/runtime/platform_apps.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('dev.clashdeck/runtime');

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    PlatformApps.clearIconCache();
  });

  test('parseInstalledApps 过滤无效项并补齐 label/system', () {
    final parsed = parseInstalledApps(<Object?>[
      <String, Object?>{'package': 'com.a', 'label': '应用 A'},
      <String, Object?>{'package': '', 'label': '空包名'},
      <String, Object?>{'label': '缺包名'},
      <String, Object?>{'package': 'com.b', 'label': 7, 'system': true},
      'not-a-map',
    ]);
    expect(parsed.map((entry) => entry.package), <String>['com.a', 'com.b']);
    expect(parsed.first.label, '应用 A');
    expect(parsed.last.label, 'com.b');
    expect(parsed.last.system, isTrue);
  });

  test('icons 批量取图标并缓存，二次请求不再过通道', () async {
    var calls = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method != 'listAppIcons') return null;
          calls++;
          final packages = (call.arguments as List).cast<String>();
          return <String, Uint8List>{
            for (final pkg in packages) pkg: Uint8List.fromList(<int>[1, 2, 3]),
          };
        });

    final first = await PlatformApps.icons(<String>['com.a', 'com.b']);
    expect(first.keys, containsAll(<String>['com.a', 'com.b']));

    final second = await PlatformApps.icons(<String>['com.a']);
    expect(second['com.a'], Uint8List.fromList(<int>[1, 2, 3]));
    expect(calls, 1);
    expect(PlatformApps.iconCacheLength, 2);
  });

  test('icons 在没有通道时返回空表而不是抛异常', () async {
    final icons = await PlatformApps.icons(<String>['com.a']);
    expect(icons, isEmpty);
  });
}
