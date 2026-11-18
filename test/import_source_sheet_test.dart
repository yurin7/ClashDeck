import 'package:clashdeck/ui/import_source_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(void Function(ImportSource?) onResult) => MaterialApp(
  home: Scaffold(
    body: Builder(
      builder: (context) => Center(
        child: FilledButton(
          onPressed: () async => onResult(await showImportSourceSheet(context)),
          child: const Text('导入'),
        ),
      ),
    ),
  ),
);

void main() {
  testWidgets('选择粘贴文本返回 paste', (tester) async {
    ImportSource? result;
    await tester.pumpWidget(_host((value) => result = value));

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    expect(find.text('粘贴文本'), findsOneWidget);
    expect(find.text('从文件选择'), findsOneWidget);
    expect(find.textContaining('.yaml / .yml / .txt'), findsOneWidget);

    await tester.tap(find.text('粘贴文本'));
    await tester.pumpAndSettle();
    expect(result, ImportSource.paste);
  });

  testWidgets('选择文件返回 file', (tester) async {
    ImportSource? result;
    await tester.pumpWidget(_host((value) => result = value));

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('从文件选择'));
    await tester.pumpAndSettle();
    expect(result, ImportSource.file);
  });

  testWidgets('点右上关闭返回 null（等于取消导入）', (tester) async {
    ImportSource? result;
    var called = false;
    await tester.pumpWidget(
      _host((value) {
        called = true;
        result = value;
      }),
    );

    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(called, isTrue);
    expect(result, isNull);
  });
}
