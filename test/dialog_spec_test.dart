import 'dart:math' as math;

import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets/edit_dialog.dart';
import 'package:clashdeck/ui/widgets/select_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  void sizeScreen(
    WidgetTester tester, {
    required double width,
    required double height,
  }) {
    tester.view.physicalSize = Size(width, height);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> open(
    WidgetTester tester,
    Future<void> Function(BuildContext) show,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => show(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  Widget tallContent() => Column(
    children: [
      for (var i = 0; i < 40; i += 1)
        SizedBox(height: 40, child: Text('第 $i 行')),
    ],
  );

  group('EditDialog', () {
    testWidgets('宽度 = min(520, 屏宽-64)', (tester) async {
      sizeScreen(tester, width: 800, height: 900);
      await open(
        tester,
        (context) => showEditDialog(
          context,
          title: '编辑规则',
          subtitle: '目标统一写入 DEFAULT',
          content: tallContent(),
        ),
      );
      final size = tester.getSize(find.byKey(const ValueKey('edit-dialog')));
      expect(size.width, 520);
    });

    testWidgets('小屏宽度 = 屏宽-64', (tester) async {
      sizeScreen(tester, width: 360, height: 700);
      await open(
        tester,
        (context) =>
            showEditDialog(context, title: '编辑规则', content: tallContent()),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('edit-dialog'))).width,
        296,
      );
    });

    testWidgets('高度封顶 min(0.8*屏高, 720)，只滚内容', (tester) async {
      sizeScreen(tester, width: 800, height: 900);
      await open(
        tester,
        (context) =>
            showEditDialog(context, title: '编辑规则', content: tallContent()),
      );
      final size = tester.getSize(find.byKey(const ValueKey('edit-dialog')));
      expect(size.height, closeTo(720, 1));
      // 标题与底部按钮固定在可视区内。
      expect(find.text('编辑规则'), findsOneWidget);
      expect(find.text('保存'), findsOneWidget);
    });

    testWidgets('按钮右对齐、最多两个，取消在保存左侧', (tester) async {
      sizeScreen(tester, width: 800, height: 900);
      await open(
        tester,
        (context) =>
            showEditDialog(context, title: '编辑规则', content: tallContent()),
      );
      expect(
        find.descendant(
          of: find.byKey(const ValueKey('edit-dialog')),
          matching: find.byType(FilledButton),
        ),
        findsOneWidget,
      );
      final cancelX = tester.getTopLeft(find.text('取消')).dx;
      final saveX = tester.getTopLeft(find.text('保存')).dx;
      expect(cancelX, lessThan(saveX));
    });
  });

  group('ConfirmDialog', () {
    testWidgets('宽度 = min(400, 屏宽-64)', (tester) async {
      sizeScreen(tester, width: 800, height: 700);
      await open(
        tester,
        (context) => showConfirmDialog(
          context,
          title: '删除这条规则？',
          message: '删除后只能重新添加。',
          confirmLabel: '删除',
          danger: true,
        ),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('confirm-dialog'))).width,
        400,
      );
    });

    testWidgets('小屏宽度 = 屏宽-64', (tester) async {
      sizeScreen(tester, width: 360, height: 700);
      await open(
        tester,
        (context) => showConfirmDialog(context, title: '删除这条规则？'),
      );
      expect(
        tester.getSize(find.byKey(const ValueKey('confirm-dialog'))).width,
        296,
      );
    });

    testWidgets('点遮罩不关闭', (tester) async {
      sizeScreen(tester, width: 800, height: 700);
      await open(
        tester,
        (context) => showConfirmDialog(context, title: '删除这条规则？'),
      );
      await tester.tapAt(const Offset(4, 4));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('删除这条规则？'), findsOneWidget);
    });
  });

  group('SelectSheet', () {
    testWidgets('高度不超过 72% 屏高', (tester) async {
      sizeScreen(tester, width: 800, height: 700);
      await open(
        tester,
        (context) => showSelectSheet<String>(
          context,
          title: '选择要加入的节点',
          subtitle: '向「默认」批量添加成员',
          body: (_) => ListView.builder(
            shrinkWrap: true,
            itemCount: 40,
            itemBuilder: (_, index) =>
                SizedBox(height: 56, child: Text('选项 $index')),
          ),
        ),
      );
      final size = tester.getSize(find.byType(BottomSheet));
      expect(size.height, lessThanOrEqualTo(math.min(700 * 0.72, 640) + 1));
    });
  });
}
