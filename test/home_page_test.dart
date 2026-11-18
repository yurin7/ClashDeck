import 'dart:io';

import 'package:clashdeck/ui/home_page.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 写死修改时间：`ProfileStore.list` 按 mtime 倒序，测试不依赖写入顺序。
void _stamp(File file, DateTime when) => file.setLastModifiedSync(when);

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
    // mtime 只有毫秒精度，几份文件连着写可能落在同一毫秒（CI 上很常见）；
    // 显式写死时间戳，让「订阅 → 坏配置 → 正常」的顺序在任何平台都稳定。
    final base = DateTime.now().subtract(const Duration(minutes: 10));
    _stamp(File('${profiles.path}/正常.yaml'), base);
    _stamp(
      File('${profiles.path}/坏配置.yaml'),
      base.add(const Duration(minutes: 1)),
    );
    _stamp(
      File('${profiles.path}/订阅.yaml'),
      base.add(const Duration(minutes: 2)),
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
    // 行尾是「编辑配置」入口（不再弹菜单），三行各一个。
    expect(find.byTooltip('编辑配置'), findsNWidgets(3));
    expect(find.text('还没有配置'), findsNothing);
  });

  testWidgets('运行配置：标「运行中」但列表顺序不变，点行回调激活、点图标进编辑器', (tester) async {
    final activated = <String>[];
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: HomePage(
          // 运行的是列表靠后的「正常」；切换时不重排，它不会顶到最前面。
          activeFileName: '正常.yaml',
          onSetActive: (fileName) async => activated.add(fileName),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.text('读取中').evaluate().isEmpty,
    );

    expect(find.text('运行中'), findsOneWidget);
    // 不置顶：「订阅」仍在「正常」之前（存储层给的顺序保持不变）。
    final subscriptionY = tester.getTopLeft(find.text('订阅').last).dy;
    final normalY = tester.getTopLeft(find.text('正常').first).dy;
    expect(subscriptionY, lessThan(normalY));

    // 点非运行的那一行 → 激活它。
    await tester.tap(find.text('订阅').last);
    await tester.pump();
    expect(activated, ['订阅.yaml']);

    // 点运行中那一行 → 不重复激活。
    await tester.tap(find.text('正常').first);
    await tester.pump();
    expect(activated, ['订阅.yaml']);
  });

  testWidgets('切换配置：那一行标「切换中」，列表顺序依然不变', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: const HomePage(
          activeFileName: '正常.yaml',
          switchingFileName: '订阅.yaml',
        ),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.text('读取中').evaluate().isEmpty,
    );

    expect(find.text('切换中'), findsOneWidget);
    // 旧配置还是运行中，直到切换完成。
    expect(find.text('运行中'), findsOneWidget);
    final subscriptionY = tester.getTopLeft(find.text('订阅').last).dy;
    final normalY = tester.getTopLeft(find.text('正常').first).dy;
    expect(subscriptionY, lessThan(normalY));

    // 切换结束后回到「运行中」。
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: const HomePage(
          activeFileName: '正常.yaml',
          switchingFileName: null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('切换中'), findsNothing);
    expect(find.text('运行中'), findsOneWidget);
  });

  testWidgets('深色：同样可渲染', (tester) async {
    await pumpHome(tester, ClashDeckTheme.dark());
    expect(find.text('读取配置失败'), findsNothing);
    expect(find.text('我的配置'), findsOneWidget);
    expect(find.text('校验通过'), findsNWidgets(2));
  });

  testWidgets('左滑露出删除，点删除走二次确认与壳层回调', (tester) async {
    final deleted = <String>[];
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: HomePage(
          activeFileName: '订阅.yaml',
          onDeleteProfile: (fileName) async => deleted.add(fileName),
        ),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.text('读取中').evaluate().isEmpty,
    );

    // 未滑动时看不到删除按钮。
    expect(find.text('删除'), findsNothing);

    // 左滑「正常」这一行 → 露出删除。
    await tester.drag(find.text('正常').first, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    // 点删除 → 二次确认弹窗。
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.text('删除「正常」？'), findsOneWidget);
    expect(find.text('删除后不可恢复，建议先备份 YAML。'), findsOneWidget);

    // 弹窗里确认 → 交给壳层回调，页面自己不动文件。
    await tester.tap(find.widgetWithText(FilledButton, '删除'));
    await tester.pumpAndSettle();
    expect(deleted, ['正常.yaml']);
    expect(find.text('删除「正常」？'), findsNothing);
    expect(File('${tmp.path}/profiles/正常.yaml').existsSync(), isTrue);
  });

  testWidgets('左滑只能展开一行，点别处自动收起', (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(theme: ClashDeckTheme.light(), home: const HomePage()),
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.text('读取中').evaluate().isEmpty,
    );

    await tester.drag(find.text('正常').first, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    // 另一行左滑 → 前一行收起，仍然只有一个删除按钮。
    await tester.drag(find.text('坏配置').first, const Offset(-140, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    // 点页面空白处 → 全部收起。
    await tester.tapAt(const Offset(180, 120));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsNothing);
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

  testWidgets('空态：只在空态里放一份入口', (tester) async {
    Directory('${tmp.path}/profiles').deleteSync(recursive: true);
    await pumpHome(tester, ClashDeckTheme.light());
    expect(find.text('还没有配置'), findsOneWidget);
    // 顶部那排「新建配置 / 导入」在空态下不渲染，避免与空态里的入口重复。
    expect(find.text('新建配置'), findsOneWidget);
    expect(find.text('导入'), findsOneWidget);
  });
}
