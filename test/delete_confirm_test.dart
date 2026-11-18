import 'package:clashdeck/ui/widgets/delete_confirm.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('确认删除返回 true，危险按钮走 error 色', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await confirmDelete(
                    context,
                    title: '删除节点「香港 01」？',
                    message: '会从所有策略组里移除它。',
                    extraHint: '2 个组引用了它：DEFAULT、PROXY。删除后会一起移除。',
                  );
                },
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();

    expect(find.text('删除节点「香港 01」？'), findsOneWidget);
    expect(find.textContaining('2 个组引用了它'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '删除'),
    );
    expect(button.style?.backgroundColor?.resolve(<WidgetState>{}), isNotNull);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(result, isTrue);
  });

  testWidgets('取消返回 false', (tester) async {
    bool? result;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  result = await confirmDelete(
                    context,
                    title: '删除「demo」？',
                    message: '删除后不可恢复。',
                  );
                },
                child: const Text('触发'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('触发'));
    await tester.pumpAndSettle();
    expect(find.text('删除「demo」？'), findsOneWidget);
    expect(find.text('删除后不可恢复。'), findsOneWidget);
    expect(find.textContaining('引用了它'), findsNothing);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
  });
}
