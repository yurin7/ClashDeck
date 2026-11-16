import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/node_form_page.dart';

void main() {
  testWidgets('编辑态带 onDelete 时出现删除按钮，确认后回调并关闭', (tester) async {
    var deleted = false;
    Map<String, Object?>? popValue;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: ElevatedButton(
                onPressed: () async {
                  popValue = await Navigator.of(context)
                      .push<Map<String, Object?>>(
                        MaterialPageRoute(
                          builder: (_) => NodeFormPage(
                            initial: const <String, Object?>{
                              'name': 'n1',
                              'type': 'vless',
                              'server': 'a.example.com',
                              'port': 443,
                              'uuid': '11111111-1111-1111-1111-111111111111',
                            },
                            onDelete: () async => deleted = true,
                          ),
                        ),
                      );
                },
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('删除节点'), findsOneWidget);
    await tester.tap(find.byTooltip('删除节点'));
    await tester.pumpAndSettle();
    expect(find.text('删除节点「n1」？'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deleted, isTrue);
    expect(popValue, isNull);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('新增态没有删除按钮', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NodeFormPage()));
    await tester.pumpAndSettle();
    expect(find.byTooltip('删除节点'), findsNothing);
  });
}
