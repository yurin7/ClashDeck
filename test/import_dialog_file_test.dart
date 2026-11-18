import 'dart:convert';
import 'dart:io';

import 'package:clashdeck/core/io/yaml_file.dart';
import 'package:clashdeck/ui/home_page.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 「导入配置」对话框里的「从文件导入」：选完回填名称/文本，用户可编辑后再导入。
///
/// 文件选择器通过 `HomePage.pickYamlFile` 注入，不依赖平台通道。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late List<PickedYamlFile?> picks;
  const channel = MethodChannel('plugins.flutter.io/path_provider');

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clashdeck_import_dialog');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.contains('ApplicationSupport')) return tmp.path;
          return null;
        });
    Directory('${tmp.path}/profiles').createSync(recursive: true);
    picks = <PickedYamlFile?>[];
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    tmp.deleteSync(recursive: true);
  });

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

  Future<void> pumpHome(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: HomePage(pickYamlFile: () async => picks.removeAt(0)),
      ),
    );
    await pumpUntil(
      tester,
      () =>
          find.byType(CircularProgressIndicator).evaluate().isEmpty &&
          find.text('读取中').evaluate().isEmpty,
    );
  }

  Future<void> openImportDialog(WidgetTester tester) async {
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    expect(find.text('导入配置'), findsOneWidget);
  }

  Future<void> pickFile(WidgetTester tester) async {
    await tester.tap(find.widgetWithText(TextButton, '从文件导入'));
    await tester.pumpAndSettle();
  }

  testWidgets('选文件后回填名称与文本，点导入创建成功', (tester) async {
    await pumpHome(tester);
    picks.add(
      PickedYamlFile(
        name: '从文件.yaml',
        bytes: Uint8List.fromList(
          utf8.encode('''
mode: rule
proxies:
  - name: n1
    type: vless
    server: n1.example.com
    port: 443
proxy-groups:
  - name: PROXY
    type: select
    proxies: [n1]
rules:
  - DOMAIN-SUFFIX,fill.example,PROXY
  - MATCH,PROXY
'''),
        ),
      ),
    );
    await openImportDialog(tester);
    await pickFile(tester);

    expect(find.text('从文件导入'), findsWidgets);
    expect(find.textContaining('fill.example'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await pumpUntil(
      tester,
      () => File('${tmp.path}/profiles/从文件.yaml').existsSync(),
    );
    expect(File('${tmp.path}/profiles/从文件.yaml').existsSync(), isTrue);
  });

  testWidgets('重名导入自动加 -2', (tester) async {
    File('${tmp.path}/profiles/从文件.yaml').writeAsStringSync('''mode: rule
''');
    await pumpHome(tester);
    picks.add(
      PickedYamlFile(
        name: '从文件.yaml',
        bytes: Uint8List.fromList(utf8.encode('mode: rule\nproxies: []\n')),
      ),
    );
    await openImportDialog(tester);
    await pickFile(tester);
    await tester.tap(find.widgetWithText(FilledButton, '导入'));
    await pumpUntil(
      tester,
      () => File('${tmp.path}/profiles/从文件-2.yaml').existsSync(),
    );
    expect(File('${tmp.path}/profiles/从文件-2.yaml').existsSync(), isTrue);
  });

  testWidgets('超过 2MB：toast 提示且保留原输入', (tester) async {
    await pumpHome(tester);
    picks.add(
      PickedYamlFile(name: '大文件.yaml', bytes: Uint8List(maxYamlFileBytes + 1)),
    );
    await openImportDialog(tester);

    // 先手填一点内容，确认失败不清空。
    final area = find.byType(TextField).last;
    await tester.enterText(area, 'keep-me');
    await tester.pump();

    await pickFile(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('文件超过 2MB，请换一份配置'), findsOneWidget);
    expect(find.text('导入配置'), findsOneWidget);
    expect(find.textContaining('keep-me'), findsOneWidget);
  });

  testWidgets('非 UTF-8：toast 提示并保留对话框', (tester) async {
    await pumpHome(tester);
    picks.add(
      PickedYamlFile(
        name: '坏编码.yaml',
        bytes: Uint8List.fromList(<int>[0xC3, 0x28]),
      ),
    );
    await openImportDialog(tester);
    await pickFile(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('文件不是 UTF-8 文本'), findsOneWidget);
    expect(find.text('导入配置'), findsOneWidget);
  });

  testWidgets('取消选择：无副作用，对话框保持', (tester) async {
    await pumpHome(tester);
    picks.add(null);
    await openImportDialog(tester);
    final before = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!
        .text;
    await pickFile(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('导入配置'), findsOneWidget);
    final after = tester
        .widget<TextField>(find.byType(TextField).last)
        .controller!
        .text;
    expect(after, before);
    expect(Directory('${tmp.path}/profiles').listSync(), isEmpty);
  });

  testWidgets('扩展名不支持：toast 提示', (tester) async {
    await pumpHome(tester);
    picks.add(
      PickedYamlFile(
        name: '配置.json',
        bytes: Uint8List.fromList(utf8.encode('{}')),
      ),
    );
    await openImportDialog(tester);
    await pickFile(tester);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('只支持 .yaml / .yml / .txt 文件'), findsOneWidget);
  });
}
