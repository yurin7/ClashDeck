import 'dart:async';

import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/sheets/sectioned_picker.dart';
import 'package:clashdeck/ui/widgets/selectable_tile.dart';
import 'package:clashdeck/ui/widgets/target_selector_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _options = <String>['PROXY', 'AUTO', 'DIRECT', 'REJECT'];
const _advanced = <String>['REJECT-DROP', 'PASS', 'COMPATIBLE', 'GLOBAL'];

Future<void> _pumpHost(
  WidgetTester tester,
  Future<void> Function(BuildContext context) open,
) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () => open(context),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

/// 打开目标面板，返回「面板关闭后」的选中值 Future。
Future<Future<String?>> _startTarget(
  WidgetTester tester, {
  String current = '',
  String? emptyLabel,
}) async {
  final completer = Completer<String?>();
  await _pumpHost(
    tester,
    (context) => showTargetPickerSheet(
      context,
      title: '规则目标',
      options: _options,
      otherOptions: _advanced,
      current: current,
      emptyLabel: emptyLabel,
      subtitles: const {'PROXY': '组 · 2'},
    ).then(completer.complete),
  );
  return completer.future;
}

bool _selectedTileFor(WidgetTester tester, String label) {
  final tile = find.ancestor(
    of: find.text(label),
    matching: find.byType(SelectableTile),
  );
  expect(tile, findsWidgets, reason: '应能找到「$label」所在行');
  return tester.widget<SelectableTile>(tile.first).selected;
}

double _top(WidgetTester tester, String text) =>
    tester.getTopLeft(find.text(text).first).dy;

void main() {
  testWidgets('目标面板：策略组 → 系统策略 → 高级内置，高级内置默认收起', (tester) async {
    await _startTarget(tester);

    expect(_top(tester, '策略组'), lessThan(_top(tester, '系统策略')));
    expect(_top(tester, '系统策略'), lessThan(_top(tester, '高级内置（不常用）（4）')));
    expect(find.text('REJECT-DROP'), findsNothing);
    expect(find.text('收起高级内置'), findsNothing);
  });

  testWidgets('目标面板：展开高级内置后四行都在并带说明', (tester) async {
    await _startTarget(tester);

    await tester.tap(find.text('高级内置（不常用）（4）'));
    await tester.pumpAndSettle();
    expect(find.text('收起高级内置'), findsOneWidget);
    expect(find.text('REJECT-DROP'), findsOneWidget);
    expect(find.text('静默丢包，不回 RST'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.text('GLOBAL'),
      120,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('PASS'), findsOneWidget);
    expect(find.text('COMPATIBLE'), findsOneWidget);
    expect(find.text('GLOBAL'), findsOneWidget);
    expect(find.text('全局出口组'), findsOneWidget);
  });

  testWidgets('目标面板：当前值高亮，点某一行返回该目标', (tester) async {
    final selected = await _startTarget(tester, current: 'PROXY');

    expect(_selectedTileFor(tester, 'PROXY'), isTrue);
    await tester.tap(find.text('DIRECT').last);
    await tester.pumpAndSettle();
    expect(await selected, 'DIRECT');
  });

  testWidgets('目标面板：空选项行可选中并返回空串', (tester) async {
    final selected = await _startTarget(tester, emptyLabel: '（默认）用规则集名称');

    await tester.tap(find.text('（默认）用规则集名称').last);
    await tester.pumpAndSettle();
    expect(await selected, '');
  });

  testWidgets('目标面板：搜索只保留匹配行，分区标题保留', (tester) async {
    await _startTarget(tester);

    await tester.enterText(find.byType(TextField).first, 'direct');
    await tester.pumpAndSettle();

    expect(find.text('DIRECT'), findsOneWidget);
    expect(find.text('PROXY'), findsNothing);
    expect(find.text('REJECT'), findsNothing);
  });

  testWidgets('全局出口四段：顺序、当前选中高亮、点节点返回', (tester) async {
    final completer = Completer<String?>();
    await _pumpHost(
      tester,
      (context) => showSectionedPicker<String>(
        context,
        title: '全局出口',
        searchHint: '搜索节点或策略组',
        sections: [
          SectionedPickerSection<String>(
            label: '跟随内核默认',
            items: [
              SectionedPickerItem(
                value: '',
                chip: const NameChip(name: '跟随内核默认'),
                searchText: '跟随内核默认',
                selected: true,
              ),
            ],
          ),
          SectionedPickerSection<String>(
            label: '系统策略',
            items: [
              for (final name in ['DIRECT', 'REJECT'])
                SectionedPickerItem(
                  value: name,
                  chip: NameChip(name: name),
                  searchText: name,
                ),
            ],
          ),
          SectionedPickerSection<String>(
            label: '策略组',
            items: [
              SectionedPickerItem(
                value: 'PROXY',
                chip: const NameChip(name: 'PROXY'),
                searchText: 'PROXY',
              ),
            ],
          ),
          SectionedPickerSection<String>(
            label: '节点',
            items: [
              SectionedPickerItem(
                value: '香港 01',
                chip: const NameChip(name: '香港 01'),
                searchText: '香港 01',
              ),
            ],
          ),
        ],
      ).then(completer.complete),
    );

    expect(_top(tester, '跟随内核默认'), lessThan(_top(tester, '系统策略')));
    expect(_top(tester, '系统策略'), lessThan(_top(tester, '策略组')));
    expect(_top(tester, '策略组'), lessThan(_top(tester, '节点')));
    expect(_selectedTileFor(tester, '跟随内核默认'), isTrue);

    await tester.tap(find.text('香港 01').last);
    await tester.pumpAndSettle();
    expect(await completer.future, '香港 01');
  });
}
