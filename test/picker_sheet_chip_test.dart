import 'package:clashdeck/ui/picker_sheet.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 打开面板，把选中结果抓回来。
Future<String? Function()> _open(
  WidgetTester tester, {
  bool chipMode = false,
  String? current,
}) async {
  String? result;
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: () async {
              result = await showPickerSheet<String>(
                tester.element(find.byType(FilledButton)),
                title: 'GLOBAL 走哪个节点',
                chipMode: chipMode,
                current: current,
                options: const [
                  PickerOption<String>(
                    'DIRECT',
                    'DIRECT',
                    icon: Icons.arrow_outward,
                    subtitle: '直连',
                  ),
                  PickerOption<String>(
                    'PROXY',
                    'PROXY',
                    icon: Icons.account_tree_outlined,
                  ),
                  PickerOption<String>(
                    'HK 01',
                    'HK 01',
                    icon: Icons.dns_outlined,
                  ),
                ],
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

void main() {
  testWidgets('胶囊模式：类型图标 + 选中勾，点一下返回该值', (tester) async {
    final result = await _open(tester, chipMode: true, current: 'DIRECT');

    expect(find.text('GLOBAL 走哪个节点'), findsOneWidget);
    // 每个选项左侧都有类型图标。
    expect(find.byIcon(Icons.arrow_outward), findsOneWidget);
    expect(find.byIcon(Icons.account_tree_outlined), findsOneWidget);
    expect(find.byIcon(Icons.dns_outlined), findsOneWidget);
    // 只有当前项带勾。
    expect(find.byIcon(Icons.check), findsOneWidget);
    // 副标题在胶囊里也能显示。
    expect(find.text('直连'), findsOneWidget);

    await tester.tap(find.text('PROXY'));
    await tester.pumpAndSettle();
    expect(result(), 'PROXY');
    expect(find.text('GLOBAL 走哪个节点'), findsNothing);
  });

  testWidgets('默认仍是整行列表：副标题可见，选中项带勾', (tester) async {
    final result = await _open(tester, current: 'HK 01');

    expect(find.text('直连'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsOneWidget);

    await tester.tap(find.text('DIRECT'));
    await tester.pumpAndSettle();
    expect(result(), 'DIRECT');
  });
}
