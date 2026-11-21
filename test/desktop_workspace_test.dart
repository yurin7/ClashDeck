import 'dart:io';
import 'dart:ui' show PointerDeviceKind;

import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/desktop_profiles.dart';
import 'package:clashdeck/ui/desktop_workspace.dart';
import 'package:clashdeck/ui/editor_page.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/raw_yaml_tab.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
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
    await tester.tap(find.text('桌面演示').first);
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

    await tester.tap(find.text('备用配置'));
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
    final library = find.byType(DesktopProfiles);
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
