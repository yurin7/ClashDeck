import 'dart:io';

import 'package:clashdeck/ui/home_page.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// HomePage 的渲染回归测试：mock 掉 path_provider，在临时目录里放三分
/// 配置（正常 / 非法 YAML / 订阅），验证品牌卡、摘要、校验状态与空态。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clashdeck_home_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.contains('ApplicationSupport')) return tmp.path;
          return null;
        });
    final profiles = Directory('${tmp.path}/profiles')
      ..createSync(recursive: true);
    File('${profiles.path}/正常.yaml').writeAsStringSync('''
mode: rule
proxies:
  - name: a
    type: vless
    server: a.example.com
    port: 443
  - name: b
    type: ss
    server: b.example.com
    port: 8388
proxy-groups:
  - name: PROXY
    type: select
    proxies: [a, b]
rules:
  - DOMAIN-SUFFIX,example.com,PROXY
  - MATCH,PROXY
''');
    File('${profiles.path}/坏配置.yaml').writeAsStringSync('proxies: [\n');
    File('${profiles.path}/订阅.yaml').writeAsStringSync('proxies: []\n');
    File('${profiles.path}/订阅.yaml.meta.json').writeAsStringSync(
      '{"subscriptionUrl":"https://sub.example.com/api?token=1"}',
    );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

  /// 页面里的配置读取是真实 IO，widget 测试的 fake async 不会推进它，
  /// 所以循环 runAsync + pump 直到条件满足。
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 400; i++) {
      if (done()) return;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
      await tester.pump(const Duration(milliseconds: 10));
    }
    fail('页面在 4s 内没有完成加载');
  }

  Future<void> pumpHome(
    WidgetTester tester,
    ThemeData theme, {
    Size physicalSize = const Size(1080, 2280),
  }) async {
    tester.view.physicalSize = physicalSize;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MaterialApp(theme: theme, home: const HomePage()));
    await pumpUntil(
      tester,
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.text('读取中').evaluate().isEmpty,
    );
  }

  testWidgets('浅色：字标、统计、坏配置与订阅状态', (tester) async {
    await pumpHome(tester, ClashDeckTheme.light());

    expect(find.text('读取配置失败'), findsNothing);
    // 字标只在 hero 里出现一次（旧设计里品牌卡还有第二处）。
    expect(find.text('ClashDeck'), findsOneWidget);
    expect(find.text('我的配置'), findsOneWidget);
    // hero 的三项统计：配置 3 / 节点 2 / 订阅 1。
    expect(find.text('3'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    expect(find.text('正常'), findsOneWidget);
    expect(find.text('坏配置'), findsOneWidget);
    expect(find.text('校验通过'), findsNWidgets(2));
    expect(find.text('↳ sub.example.com'), findsOneWidget);
    expect(find.byTooltip('更多操作'), findsNWidgets(3));
    expect(find.text('还没有配置'), findsNothing);
  });

  testWidgets('深色：同样可渲染', (tester) async {
    await pumpHome(tester, ClashDeckTheme.dark());
    expect(find.text('读取配置失败'), findsNothing);
    expect(find.text('我的配置'), findsOneWidget);
    expect(find.text('校验通过'), findsNWidgets(2));
  });

  testWidgets('360dp 窄屏：长错误标签不溢出', (tester) async {
    // physicalSize 是物理像素，除以 dpr 3 后逻辑宽度正好 360dp。
    await pumpHome(
      tester,
      ClashDeckTheme.light(),
      physicalSize: const Size(1080, 2280),
    );
    // 布局溢出会以 FlutterError 记入测试；这里再确认坏配置行确实已布局。
    expect(find.text('坏配置'), findsOneWidget);
    expect(find.text('校验通过'), findsNWidgets(2));
  });

  testWidgets('空态：EmptyHint 与两个入口按钮', (tester) async {
    Directory('${tmp.path}/profiles').deleteSync(recursive: true);
    await pumpHome(tester, ClashDeckTheme.light());
    expect(find.text('还没有配置'), findsOneWidget);
    expect(find.text('新建配置'), findsNWidgets(2));
    expect(find.text('导入'), findsNWidgets(2));
  });
}
