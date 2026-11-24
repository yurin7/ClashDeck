import 'dart:io';
import 'dart:ui' show ImageByteFormat, PointerDeviceKind;

import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/desktop_hover.dart';
import 'package:clashdeck/ui/desktop_profiles.dart';
import 'package:clashdeck/ui/desktop_window.dart';
import 'package:clashdeck/ui/desktop_workspace.dart';
import 'package:clashdeck/ui/editor_page.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/raw_yaml_tab.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('悬停时控件跟随鼠标微倾，点击范围保持稳定', (tester) async {
    var clicks = 0;
    const buttonKey = ValueKey('hover-button');
    Future<void> show({bool reduceMotion = false}) => tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: DesktopHover(
              borderRadius: BorderRadius.circular(Radiuses.md),
              lift: 3,
              tilt: 0.055,
              child: SizedBox(
                width: 148,
                height: 46,
                key: buttonKey,
                child: FilledButton(
                  onPressed: () => clicks++,
                  child: const Text('启动内核'),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await show();
    final control = find.byKey(buttonKey);
    final resting = tester.getRect(control);
    final outside = resting.topLeft - const Offset(30, 30);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: outside);
    await mouse.moveTo(resting.center);
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(control).dy, closeTo(resting.top - 3, 0.1));

    await mouse.moveTo(resting.centerLeft + const Offset(12, 0));
    await tester.pump();
    final leftLean = tester.getTopLeft(control);
    await mouse.moveTo(resting.centerRight - const Offset(12, 0));
    await tester.pump();
    expect(tester.getTopLeft(control), isNot(leftLean));
    await tester.tapAt(resting.bottomCenter - const Offset(0, 1));
    expect(clicks, 1);

    await mouse.moveTo(outside);
    await tester.pumpAndSettle();
    expect(tester.getRect(control), resting);
    await show(reduceMotion: true);
    await mouse.moveTo(resting.center);
    await tester.pumpAndSettle();
    expect(tester.getRect(control), resting);
    await mouse.removePointer();
  });

  testWidgets('鼠标离开窗口按钮后恢复初始底色', (tester) async {
    final boundaryKey = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        builder: (context, child) => RepaintBoundary(
          key: boundaryKey,
          child: DesktopWindowFrame(child: child),
        ),
        home: const Scaffold(),
      ),
    );
    Future<int?> sample(Offset point) => tester.runAsync(() async {
      final boundary =
          boundaryKey.currentContext!.findRenderObject()!
              as RenderRepaintBoundary;
      final image = await boundary.toImage();
      try {
        final rgba = await image.toByteData(format: ImageByteFormat.rawRgba);
        final local = boundary.globalToLocal(point);
        return rgba!.getUint32(
          (image.width * local.dy.floor() + local.dx.floor()) * 4,
        );
      } finally {
        image.dispose();
      }
    });

    final caption = tester.getTopLeft(find.byType(DesktopWindowCaption));
    final outside = caption + const Offset(-30, 16);
    final inside = caption + const Offset(12, 16);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: outside);
    await tester.pumpAndSettle();
    final initial = await sample(inside);
    expect(initial, isNotNull);

    await mouse.moveTo(inside);
    await tester.pumpAndSettle();
    expect(find.text('最小化'), findsOneWidget);
    expect(await sample(inside), isNot(initial));

    await mouse.moveTo(outside);
    await tester.pumpAndSettle();
    expect(find.text('最小化'), findsNothing);
    expect(await sample(inside), initial);
    await mouse.removePointer();
  });

  testWidgets('桌面工作区切换配置前保留修改，Ctrl+S 保存源码', (tester) async {
    final workspace = Directory.systemTemp.createTempSync('clashdeck_desktop_');
    addTearDown(() => workspace.deleteSync(recursive: true));
    const paths = MethodChannel('plugins.flutter.io/path_provider');
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(paths, (_) async => workspace.path);
    addTearDown(() => messenger.setMockMethodCallHandler(paths, null));
    final directory = Directory('${workspace.path}/profiles')..createSync();
    final config = ProfileStore.starterConfig(name: '桌面演示').replaceFirst(
      'rules:',
      'rules:\n  - DOMAIN-SUFFIX,editor.example.org,DIRECT',
    );
    final active = File('${directory.path}/桌面演示.yaml')
      ..writeAsStringSync(config);
    File('${directory.path}/备用配置.yaml')
      ..writeAsStringSync(ProfileStore.starterConfig(name: '备用配置'))
      ..setLastModifiedSync(
        active.lastModifiedSync().subtract(const Duration(minutes: 1)),
      );
    File('${directory.path}/备用配置.yaml.meta.json')
        .writeAsStringSync('{"imported":true}');

    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark().copyWith(platform: TargetPlatform.windows),
        home: DesktopWorkspace(store: ProfileStore(directory)),
      ),
    );
    await _pumpUntil(tester, () => find.text('实时流量').evaluate().isNotEmpty);
    expect(find.text('下载'), findsOneWidget);
    expect(find.text('上传'), findsOneWidget);
    expect(find.text('节点测速'), findsOneWidget);
    expect(find.text('备用配置'), findsNothing);
    expect(find.text('我的配置'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    final library = find.byType(DesktopProfiles);
    final search = find.descendant(
      of: library,
      matching: find.byType(TextField),
    );
    expect(tester.widget<TextField>(search).focusNode?.hasFocus, isTrue);
    await tester.enterText(search, '备用');
    await tester.pumpAndSettle();
    expect(find.text('桌面演示'), findsNothing);
    expect(find.text('备用配置'), findsOneWidget);
    await tester.tap(find.byTooltip('清除搜索'));
    await tester.pumpAndSettle();
    final originalCard = find.ancestor(
      of: find.text('桌面演示'),
      matching: find.byType(AppCard),
    );
    await tester.tap(
      find.descendant(of: originalCard, matching: find.byTooltip('编辑配置')),
    );
    await _pumpUntil(tester, () => find.text('节点列表').evaluate().isNotEmpty);
    expect(find.text('策略组'), findsOneWidget);

    await tester.tap(find.text('YAML'));
    await tester.pumpAndSettle();
    final source = find.descendant(
      of: find.byType(RawYamlTab),
      matching: find.byType(TextField),
    );
    final draft = '# 桌面更新\n${active.readAsStringSync()}';
    await tester.enterText(source, draft);
    await tester.pump();

    await tester.tap(find.widgetWithText(ListTile, '配置'));
    await tester.pumpAndSettle();
    expect(find.text('有未保存的改动'), findsOneWidget);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(find.text('桌面演示.yaml'), findsOneWidget);
    expect(active.readAsStringSync(), isNot(startsWith('# 桌面更新')));

    await tester.tap(source);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyS);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await _pumpUntil(
      tester,
      () => active.readAsStringSync().startsWith('# 桌面更新'),
    );
    await _pumpUntil(
      tester,
      () => !tester.state<EditorPageState>(find.byType(EditorPage)).saving,
    );

    tester.view.physicalSize = const Size(820, 560);
    await tester.pumpAndSettle();
    await tester.tap(find.text('分流规则'));
    await tester.pumpAndSettle();
    expect(find.text('editor.example.org'), findsOneWidget);
    await tester.tap(find.text('代理与策略组'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(ListTile, '概览'));
    await _pumpUntil(tester, () => find.text('实时流量').evaluate().isNotEmpty);
    await tester.tap(find.text('切换配置'));
    await tester.pumpAndSettle();
    final imported = find.descendant(of: library, matching: find.text('备用配置'));
    expect(
      find.descendant(
        of: library,
        matching: find.byIcon(Icons.file_download_outlined),
      ),
      findsNWidgets(2),
    );
    await tester.tap(imported);
    final preferences = File('${workspace.path}/app_prefs.json');
    final create = find.descendant(
      of: library,
      matching: find.byType(AccentButton),
    );
    await _pumpUntil(
      tester,
      () =>
          tester.widget<AccentButton>(create).onPressed != null &&
          preferences.existsSync() &&
          preferences.readAsStringSync().contains('备用配置.yaml'),
    );
    await tester.pumpAndSettle();
    expect(find.byType(EditorPage), findsNothing);
    final importedCard = find.ancestor(
      of: imported,
      matching: find.byType(AppCard),
    );
    await tester.tap(
      find.descendant(of: importedCard, matching: find.byTooltip('配置操作')),
    );
    await tester.pumpAndSettle();
    expect(find.text('重命名'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    await tester.enterText(find.widgetWithText(TextField, '搜索操作或配置'), '查看');
    await tester.pumpAndSettle();
    expect(find.text('查看连接'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(find.text('暂无内核日志'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Windows 鼠标移动时立即拾取节点并加入策略组', (tester) async {
    final state = EditorState.fromText('''
proxies:
  - {name: 东京, type: http, server: example.org, port: 8080}
proxy-groups:
  - {name: 出口, type: select, proxies: [DIRECT]}
rules:
  - MATCH,出口
''');
    tester.view.physicalSize = const Size(1140, 780);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark().copyWith(platform: TargetPlatform.windows),
        home: Scaffold(body: ProxyBoard(state: state, desktop: true)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byTooltip('添加成员'), findsWidgets);
    expect(find.byTooltip('策略组操作'), findsWidgets);
    final from = tester.getCenter(find.text('东京').first);
    final to = tester.getCenter(find.text('出口'));
    final gesture = await tester.startGesture(
      from,
      kind: PointerDeviceKind.mouse,
    );
    await gesture.moveBy(const Offset(30, 0));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(state.profile.group('出口')?.members, contains('东京'));
  });
}

Future<void> _pumpUntil(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 300 && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  }
  expect(done(), isTrue);
}
