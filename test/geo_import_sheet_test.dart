import 'package:clashdeck/core/edit/rule_presets.dart';
import 'package:clashdeck/ui/rules/geo_import_sheet.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 打开 GEO 面板，返回一个读取最终结果的闭包。
Future<List<String>? Function()> _open(
  WidgetTester tester, {
  Set<String> existing = const <String>{},
}) async {
  List<String>? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              result = await showGeoImportSheet(
                tester.element(find.byType(FilledButton)),
                existingCodes: existing,
              );
            },
            child: const Text('open'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => result;
}

/// 「厂商」分类里可选（未在配置里）的词库数。
int get _vendorTotal =>
    kGeositePicks.where((pick) => pick.group == '厂商').length;

/// 卸载面板并走完 `disposeAfterDialog` 的 600ms 延迟，避免残留 Timer。
Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 700));
}

void main() {
  testWidgets('左右滑动切换分类：chips 高亮跟随，面板高度不变', (tester) async {
    final read = await _open(tester);
    final sheet = find.byKey(const ValueKey('geo-import-sheet'));
    final height = tester.getSize(sheet).height;

    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, '厂商')).selected,
      isTrue,
    );

    await tester.fling(find.byType(PageView), const Offset(-320, 0), 1200);
    await tester.pumpAndSettle();

    expect(
      tester.widget<ChoiceChip>(find.widgetWithText(ChoiceChip, 'AI')).selected,
      isTrue,
    );
    expect(tester.getSize(sheet).height, height);
    expect(find.text('openai'), findsOneWidget);

    await tester.tap(find.text('openai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 1 条'));
    await tester.pumpAndSettle();
    expect(read(), <String>['openai']);
    await _drain(tester);
  });

  testWidgets('当前分类全选 / 清空：计数与提交按钮一致', (tester) async {
    await _open(tester);

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 $_vendorTotal'), findsOneWidget);
    expect(find.text('添加 $_vendorTotal 条'), findsOneWidget);

    await tester.tap(find.text('清空'));
    await tester.pumpAndSettle();
    expect(find.text('已选 0'), findsOneWidget);
    expect(find.text('添加 0 条'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('已在配置里的词库显示「已添加」且不计入全选', (tester) async {
    await _open(tester, existing: const <String>{'microsoft'});

    await tester.tap(find.text('全选'));
    await tester.pumpAndSettle();
    expect(find.text('已选 ${_vendorTotal - 1}'), findsOneWidget);
    expect(find.text('已添加'), findsOneWidget);
    await _drain(tester);
  });

  testWidgets('搜索无结果时可「直接使用」输入的 code', (tester) async {
    final read = await _open(tester);

    await tester.enterText(find.byType(TextField), 'no-such-geosite');
    await tester.pumpAndSettle();
    expect(find.text('＋ 直接使用 no-such-geosite'), findsOneWidget);

    await tester.tap(find.text('＋ 直接使用 no-such-geosite'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 1 条'));
    await tester.pumpAndSettle();
    expect(read(), <String>['no-such-geosite']);
    await _drain(tester);
  });
}
