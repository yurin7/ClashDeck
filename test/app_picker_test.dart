import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:clashdeck/runtime/platform_apps.dart';
import 'package:clashdeck/ui/app_picker_page.dart';
import 'package:clashdeck/ui/navigation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 1×1 透明 PNG：只验证「有字节就渲染 Image」，不依赖真实图标。
final Uint8List _tinyPng = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

const _apps = <AppEntry>[
  AppEntry(package: 'com.bilibili', label: '哔哩哔哩'),
  AppEntry(package: 'com.example.maps', label: '地图'),
];

List<String>? _result;

Future<void> _open(
  WidgetTester tester, {
  AppListLoader? loader,
  AppIconLoader? icons,
  List<String> selected = const [],
  Duration minimum = const Duration(milliseconds: 120),
}) async {
  _result = null;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                _result = await Navigator.of(context).push<List<String>>(
                  appRoute<List<String>>(
                    AppPickerPage(
                      selected: selected,
                      title: '选择应用',
                      appLoader: loader ?? () async => _apps,
                      iconLoader: icons ?? (_) async => const {},
                      minimumLoad: minimum,
                    ),
                  ),
                );
              },
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pump();
  // 路由第一帧才真正构建新页面，再走 1ms 让骨架稳定可见。
  await tester.pump(const Duration(milliseconds: 1));
}

void main() {
  testWidgets('进入页面先出骨架，最短 120ms 后才出列表', (tester) async {
    await _open(tester);
    expect(find.byKey(const Key('app-picker-skeleton')), findsOneWidget);
    expect(find.text('哔哩哔哩'), findsNothing);

    await tester.pump(const Duration(milliseconds: 60));
    expect(find.byKey(const Key('app-picker-skeleton')), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 80));
    expect(find.byKey(const Key('app-picker-skeleton')), findsNothing);
    expect(find.text('哔哩哔哩'), findsOneWidget);
  });

  testWidgets('没有图标字节时用首字母占位', (tester) async {
    await _open(tester, minimum: Duration.zero);
    await tester.pump();
    expect(find.byType(Image), findsNothing);
    expect(find.text('哔'), findsOneWidget);
    expect(find.text('地'), findsOneWidget);
  });

  testWidgets('有图标字节时渲染 Image，尺寸统一 32', (tester) async {
    await _open(
      tester,
      minimum: Duration.zero,
      icons: (packages) async => {for (final pkg in packages) pkg: _tinyPng},
    );
    await tester.pump();
    await tester.pump();
    final images = tester.widgetList<Image>(find.byType(Image));
    expect(images, isNotEmpty);
    for (final image in images) {
      expect(image.width, 32);
      expect(image.height, 32);
    }
  });

  testWidgets('图标按批异步补入，不挡列表首帧', (tester) async {
    final gate = Completer<Map<String, Uint8List>>();
    await _open(tester, minimum: Duration.zero, icons: (_) => gate.future);
    await tester.pump();
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.byType(Image), findsNothing);

    gate.complete({for (final app in _apps) app.package: _tinyPng});
    await tester.pump();
    await tester.pump();
    expect(find.byType(Image), findsNWidgets(2));
  });

  testWidgets('点选累积、清空、完成后返回选中包名', (tester) async {
    await _open(
      tester,
      minimum: Duration.zero,
      selected: const ['com.bilibili'],
    );
    await tester.pump(const Duration(milliseconds: 320));
    expect(find.text('已选 1 个'), findsOneWidget);

    await tester.tap(find.text('地图'));
    await tester.pump();
    expect(find.text('已选 2 个'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pump();
    expect(find.text('已选 0 个'), findsOneWidget);

    await tester.tap(find.text('地图'));
    await tester.pump();
    await tester.tap(find.text('完成'));
    await tester.pumpAndSettle();
    expect(_result, ['com.example.maps']);
  });

  testWidgets('搜索按应用名或包名过滤，无结果给提示', (tester) async {
    await _open(tester, minimum: Duration.zero);
    await tester.pump();

    await tester.enterText(find.byType(TextField), 'bili');
    await tester.pump();
    expect(find.text('哔哩哔哩'), findsOneWidget);
    expect(find.text('地图'), findsNothing);

    await tester.enterText(find.byType(TextField), 'zzz');
    await tester.pump();
    expect(find.textContaining('没有匹配'), findsOneWidget);
  });

  testWidgets('平台没有应用清单时显示空态而不是一直骨架', (tester) async {
    await _open(tester, loader: () async => const [], minimum: Duration.zero);
    await tester.pump();
    expect(find.text('拿不到应用列表'), findsOneWidget);
  });
}
