import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/ui/fields.dart';

void main() {
  testWidgets('多行文本域：宽度撑满、高度约 0.8×宽度、框内滚动', (tester) async {
    final controller = TextEditingController(text: 'https://example.com/sub');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              child: AppTextArea(controller: controller, label: '订阅地址'),
            ),
          ),
        ),
      ),
    );

    final area = find.byType(AppTextArea);
    expect(area, findsOneWidget);
    expect(tester.getSize(area).width, 400);
    // 0.8 × 400 = 320，正好等于上限。
    expect(tester.getSize(area).height, 320);

    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.expands, isTrue);
    expect(field.minLines, isNull);
    expect(field.maxLines, isNull);
    expect(field.keyboardType, TextInputType.multiline);
    expect(field.textAlignVertical, TextAlignVertical.top);
  });

  testWidgets('多行文本域：窄屏按比例缩小并保住下限', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 300,
              child: AppTextArea(controller: TextEditingController()),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppTextArea)).height, 240);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 100,
              child: AppTextArea(controller: TextEditingController()),
            ),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(AppTextArea)).height, 110);
  });
}
