import 'dart:io';

import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/update/update_check.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/app_prefs.dart';
import 'package:clashdeck/ui/pulse_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
mixed-port: 7890
proxies:
  - name: HK-01
    type: ss
    server: 1.1.1.1
    port: 8388
    cipher: aes-128-gcm
    password: pw
  - name: JP-01
    type: ss
    server: 1.1.1.2
    port: 8388
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - HK-01
      - JP-01
rules:
  - MATCH,PROXY
''';

UpdateInfo _info() => UpdateInfo(
  version: '0.3.0',
  url: 'https://github.com/yurin7/ClashDeck/releases/tag/v0.3.0',
  notes: '- 新增 Pulse\n- 修复 A',
  publishedAt: DateTime(2026, 11, 19),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;
  late AppPrefs prefs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clashdeck_pulse');
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

  Future<void> loadPrefs(WidgetTester tester) async {
    await tester.runAsync(() async {
      prefs = await AppPrefs.load();
    });
  }

  Widget host(Widget child) => MaterialApp(home: child);

  PulsePage page({
    Future<UpdateCheckResult> Function(String)? checkUpdate,
    Future<bool> Function(String)? openUrl,
    Future<void> Function()? startKernel,
  }) => PulsePage(
    appVersion: '0.2.1',
    profileName: 'demo',
    profile: Profile.from(YamlDoc.parse(_yaml)),
    prefs: prefs,
    checkUpdate: checkUpdate,
    openUrl: openUrl,
    startKernel: startKernel,
  );

  testWidgets('四张卡都在，内核未运行时提示先启动', (tester) async {
    await loadPrefs(tester);
    await tester.pumpWidget(host(page()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('ClashDeck'), findsOneWidget);
    expect(find.text('节点测速'), findsOneWidget);
    expect(find.text('启动内核后可测速'), findsOneWidget);
    expect(find.text('检查更新'), findsWidgets);
    expect(find.text('运行状态'), findsOneWidget);
    expect(find.text('当前配置'), findsOneWidget);
    expect(find.text('demo'), findsWidgets);
    // 内核未运行且没有缓存：不给选择器/节点列表，只留说明和启动按钮。
    expect(find.textContaining('全选'), findsNothing);
    expect(find.text('HK-01'), findsNothing);
  });

  testWidgets('缓存里的延迟按升序排列，超时排在最后', (tester) async {
    await loadPrefs(tester);
    await tester.runAsync(() async {
      await prefs.setLatencies('demo', {
        'HK-01': 320,
        'JP-01': null,
      }, at: DateTime(2026, 11, 19, 1, 2));
    });
    await tester.pumpWidget(host(page()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('320 ms'), findsOneWidget);
    expect(find.text('超时'), findsOneWidget);
    expect(find.textContaining('上次结果'), findsOneWidget);
    expect(find.text('全选 2 个'), findsOneWidget);

    final slow = tester.getTopLeft(find.text('320 ms')).dy;
    final timeout = tester.getTopLeft(find.text('超时')).dy;
    expect(slow, lessThan(timeout));
  });

  testWidgets('检查更新发现新版显示去查看，点击打开浏览器', (tester) async {
    await loadPrefs(tester);
    var opened = '';
    await tester.pumpWidget(
      host(
        page(
          checkUpdate: (_) async => UpdateAvailable(_info()),
          openUrl: (url) async {
            opened = url;
            return true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('检查更新').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('发现 0.3.0'), findsOneWidget);
    await tester.tap(find.text('去查看'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, contains('v0.3.0'));
  });

  testWidgets('已是最新版本时轻提示', (tester) async {
    await loadPrefs(tester);
    await tester.pumpWidget(
      host(page(checkUpdate: (_) async => UpToDate(_info()))),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('检查更新').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('已是最新版本'), findsWidgets);
  });

  testWidgets('启动内核按钮回调注入的 startKernel', (tester) async {
    await loadPrefs(tester);
    var started = 0;
    await tester.pumpWidget(host(page(startKernel: () async => started++)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('启动内核'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(started, 1);
  });
}
