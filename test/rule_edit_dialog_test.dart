import 'package:clashdeck/ui/rule_edit_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpHost(
    WidgetTester tester,
    void Function(BuildContext context) onPressed,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => onPressed(context),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('新建规则：点遮罩自动保存草稿', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'PROXY', 'DEFAULT'],
        isNew: true,
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('新建规则'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'google.com');
    // 点对话框外面 = 保存关闭。
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.type, 'DOMAIN-SUFFIX');
    expect(saved!.payload, 'google.com');
    expect(saved!.target, 'DEFAULT'); // 目标里含 DEFAULT 时默认写 DEFAULT。
  });

  testWidgets('校验不过时点遮罩不关闭，点关闭按钮才保存', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: true,
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tapAt(const Offset(8, 8));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('新建规则'), findsOneWidget);
    expect(find.text('请填写匹配内容'), findsOneWidget);
    expect(saved, isNull);

    await tester.enterText(find.byType(TextField), 'google.com');
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(seconds: 4)); // 清掉 toast 计时器。

    expect(saved, isNotNull);
    expect(saved!.payload, 'google.com');
  });

  testWidgets('编辑规则没有保存/取消/删除按钮', (tester) async {
    await pumpHost(tester, (context) async {
      await showRuleEditDialog(
        context,
        initialType: 'DOMAIN-SUFFIX',
        initialPayload: 'google.com',
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: false,
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('编辑规则'), findsOneWidget);
    expect(find.text('保存'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(find.text('删除'), findsNothing);
  });

  testWidgets('MATCH 不需要匹配内容，点遮罩直接保存', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        initialType: 'MATCH',
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: false,
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('匹配内容'), findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.type, 'MATCH');
    expect(saved!.payload, '');
    expect(saved!.target, 'DEFAULT');
  });

  testWidgets('编辑规则：高级内置默认折叠，展开后四个都在', (tester) async {
    await pumpHost(tester, (context) async {
      await showRuleEditDialog(
        context,
        initialType: 'DOMAIN-SUFFIX',
        initialPayload: 'google.com',
        targets: const ['DIRECT', 'DEFAULT'],
        otherBuiltins: const ['REJECT-DROP', 'PASS', 'COMPATIBLE', 'GLOBAL'],
        isNew: false,
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('高级内置（不常用）（4）'), findsNothing);
    await tester.tap(find.text('目标（策略 / 组）'));
    await tester.pumpAndSettle();

    expect(find.text('高级内置（不常用）（4）'), findsOneWidget);
    expect(find.text('REJECT-DROP'), findsNothing);

    await tester.tap(find.text('高级内置（不常用）（4）'));
    await tester.pumpAndSettle();
    expect(find.text('收起高级内置'), findsOneWidget);
    expect(find.text('REJECT-DROP'), findsOneWidget);
    expect(find.text('PASS'), findsOneWidget);
    // 折叠区在可滚动列表里，后两条需要滚出来。
    await tester.drag(find.byType(ListView).last, const Offset(0, -240));
    await tester.pumpAndSettle();
    expect(find.text('COMPATIBLE'), findsOneWidget);
    expect(find.text('GLOBAL'), findsOneWidget);

    // 关掉目标面板，再点遮罩关掉规则弹窗。
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
  });

  testWidgets('新增规则不出现高级内置', (tester) async {
    await pumpHost(tester, (context) async {
      await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'DEFAULT'],
        otherBuiltins: const ['REJECT-DROP', 'PASS'],
        isNew: true,
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('目标（策略 / 组）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('高级内置'), findsNothing);
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
  });

  testWidgets('目标包含 DEFAULT 时默认目标为 DEFAULT', (tester) async {
    await pumpHost(tester, (context) async {
      await showRuleEditDialog(
        context,
        targets: const ['PROXY', 'DEFAULT'],
        isNew: true,
      );
    });
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.text('DEFAULT'), findsOneWidget);
    expect(find.text('PROXY'), findsNothing);
  });
}
