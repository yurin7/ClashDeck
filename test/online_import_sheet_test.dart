import 'package:clashdeck/core/edit/rule_presets.dart';
import 'package:clashdeck/ui/rules/online_import_sheet.dart';
import 'package:clashdeck/ui/widgets/selectable_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('已添加的规则集默认勾选、带「已添加」且点不动', (tester) async {
    await tester.pumpWidget(const _Host(existing: {'loyal-reject'}));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.text('已添加'), findsWidgets);
    // 已有项计入初始选择，但按钮只算新增 → 0，且置灰。
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull);
    expect(find.text('导入 0 个'), findsOneWidget);

    final tile = find.ancestor(
      of: find.text('已添加'),
      matching: find.byType(SelectableTile),
    );
    final before = tester.widget<SelectableTile>(tile).selected;
    await tester.tap(tile);
    await tester.pump();
    expect(tester.widget<SelectableTile>(tile).selected, before);
    expect(find.text('导入 0 个'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('全选只选非已添加项，计数只算新增，提交不含已添加', (tester) async {
    await tester.pumpWidget(const _Host(existing: {'loyal-reject'}));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    await tester.tap(find.text('全部'));
    await tester.pump();

    final total = _uniquePresetCount();
    expect(find.text('导入 ${total - 1} 个'), findsOneWidget);

    await tester.tap(find.byType(FilledButton));
    await tester.pumpAndSettle();

    final result = _Host.result as OnlinePresetRequest?;
    expect(result, isNotNull);
    expect(
      result!.presets.any((preset) => preset.id == 'loyal-reject'),
      isFalse,
    );
    expect(result.presets.length, total - 1);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 700));
  });

  testWidgets('不传 existingIds 时没有「已添加」，全选全算', (tester) async {
    await tester.pumpWidget(const _Host(existing: <String>{}));
    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();

    expect(find.text('已添加'), findsNothing);
    await tester.tap(find.text('全部'));
    await tester.pump();
    final total = _uniquePresetCount();
    expect(find.text('导入 $total 个'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(milliseconds: 700));
  });
}

/// 两个分组里可能有同 id，按去重后的数量算。
int _uniquePresetCount() => {
  for (final preset in kLoyalRulesPresets) preset.id,
  for (final preset in kAclRulesPresets) preset.id,
}.length;

class _Host extends StatelessWidget {
  const _Host({required this.existing});

  final Set<String> existing;

  static OnlineImportRequest? result;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Builder(
        builder: (context) => Center(
          child: TextButton(
            key: const ValueKey('open'),
            onPressed: () async {
              result = await showOnlineImportSheet(
                context,
                existingIds: existing,
              );
            },
            child: const Text('打开'),
          ),
        ),
      ),
    );
  }
}
