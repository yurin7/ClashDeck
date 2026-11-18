import 'package:clashdeck/ui/fields.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('helper / error 最多两行，长文案不撑破弹窗', (tester) async {
    const helper =
        '会作为文件名保存，可直接被 mihomo 读取；名称里不要带 / 和空格，'
        '改完以后旧配置不会自动迁移，需要手动改回。';
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 280,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  AppTextField(label: '名称', helper: helper),
                  SizedBox(height: 12),
                  AppTextField(label: '名称', error: helper),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final fields = tester
        .widgetList<TextField>(find.byType(TextField))
        .toList();
    expect(fields, hasLength(2));
    for (final field in fields) {
      expect(field.decoration?.helperMaxLines, 2);
      expect(field.decoration?.errorMaxLines, 2);
    }

    // 两处提示各自最多两行：高度不超过三行字号，且没有溢出异常。
    for (final finder in [find.text(helper).first, find.text(helper).last]) {
      expect(tester.getSize(finder).height, lessThan(56));
    }
    expect(tester.takeException(), isNull);
  });
}
