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

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  Future<void> tapBarrier(WidgetTester tester) async {
    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
  }

  testWidgets('新建规则空内容点遮罩：静默退出，不崩不落盘', (tester) async {
    var called = false;
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      called = true;
      saved = await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: true,
      );
    });
    await open(tester);
    expect(find.text('新建规则'), findsOneWidget);

    await tapBarrier(tester);

    expect(called, isTrue);
    expect(saved, isNull);
    expect(find.text('新建规则'), findsNothing);
    expect(find.text('内容无效，未保存'), findsNothing);
  });

  testWidgets('新建规则半填点遮罩：丢弃草稿，不提示不落盘', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: true,
      );
    });
    await open(tester);
    await tester.enterText(find.byType(TextField), 'google.com');

    await tapBarrier(tester);

    expect(saved, isNull);
    expect(find.text('新建规则'), findsNothing);
    expect(find.text('内容无效，未保存'), findsNothing);
  });

  testWidgets('新建规则点右上关闭：同样静默退出', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: true,
        initialPayload: 'half',
      );
    });
    await open(tester);

    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(saved, isNull);
    expect(find.text('新建规则'), findsNothing);
  });

  testWidgets('新建规则：填好后点「添加」保存', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: true,
      );
    });
    await open(tester);

    expect(find.text('添加'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'google.com');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(saved, isNotNull);
    expect(saved!.payload, 'google.com');
    expect(saved!.target, 'DEFAULT');
    expect(find.text('新建规则'), findsNothing);
  });

  testWidgets('新建规则：内容为空点「添加」留在窗口并提示', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: true,
      );
    });
    await open(tester);

    await tester.tap(find.text('添加'));
    await tester.pump(const Duration(milliseconds: 300));

    expect(saved, isNull);
    expect(find.text('新建规则'), findsOneWidget);
    expect(find.text('请填写匹配内容'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tapBarrier(tester);
  });

  testWidgets('编辑规则合法内容点遮罩：保存并关闭', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        initialType: 'DOMAIN-SUFFIX',
        initialPayload: 'google.com',
        initialTarget: 'PROXY',
        targets: const ['PROXY', 'DEFAULT'],
        isNew: false,
      );
    });
    await open(tester);
    expect(find.text('编辑规则'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'example.com');
    await tapBarrier(tester);

    expect(saved, isNotNull);
    expect(saved!.payload, 'example.com');
    expect(saved!.target, 'PROXY');
    expect(find.text('编辑规则'), findsNothing);
  });

  testWidgets('编辑规则非法内容点遮罩：丢弃改动并提示', (tester) async {
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        initialType: 'DOMAIN-SUFFIX',
        initialPayload: 'google.com',
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: false,
      );
    });
    await open(tester);
    await tester.enterText(find.byType(TextField), '');

    await tapBarrier(tester);
    expect(find.text('内容无效，未保存'), findsOneWidget);
    expect(saved, isNull);
    expect(find.text('编辑规则'), findsNothing);

    await tester.pump(const Duration(seconds: 4)); // 清 toast 计时器。
  });

  testWidgets('编辑规则有删除入口，新建没有', (tester) async {
    var deleted = 0;
    RuleDraft? saved;
    await pumpHost(tester, (context) async {
      saved = await showRuleEditDialog(
        context,
        initialType: 'DOMAIN-SUFFIX',
        initialPayload: 'google.com',
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: true,
      );
      saved = await showRuleEditDialog(
        context,
        initialType: 'DOMAIN-SUFFIX',
        initialPayload: 'google.com',
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: false,
        onDelete: () async {
          deleted++;
          return true;
        },
      );
    });
    await open(tester);
    // pumpHost 连续弹两个，先关掉新建那个。
    expect(find.byTooltip('删除这条规则'), findsNothing);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();

    expect(find.text('编辑规则'), findsOneWidget);
    expect(find.byTooltip('删除这条规则'), findsOneWidget);
    await tester.tap(find.byTooltip('删除这条规则'));
    await tester.pumpAndSettle();

    expect(deleted, 1);
    expect(saved, isNull); // 删除后直接关窗，不返回草稿。
    expect(find.text('编辑规则'), findsNothing);
  });

  testWidgets('规则弹窗没有保存/取消/删除文字按钮', (tester) async {
    await pumpHost(tester, (context) async {
      await showRuleEditDialog(
        context,
        initialType: 'DOMAIN-SUFFIX',
        initialPayload: 'google.com',
        targets: const ['DIRECT', 'DEFAULT'],
        isNew: false,
        onDelete: () async => false,
      );
    });
    await open(tester);

    expect(find.text('保存'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(find.text('删除'), findsNothing);
    await tapBarrier(tester);
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
    await open(tester);

    expect(find.text('匹配内容'), findsNothing);
    await tapBarrier(tester);

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
    await open(tester);

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
    await tapBarrier(tester);
    await tapBarrier(tester);
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
    await open(tester);

    await tester.tap(find.text('目标（策略 / 组）'));
    await tester.pumpAndSettle();
    expect(find.textContaining('高级内置'), findsNothing);
    await tapBarrier(tester);
    await tapBarrier(tester);
  });

  testWidgets('目标包含 DEFAULT 时默认目标为 DEFAULT', (tester) async {
    await pumpHost(tester, (context) async {
      await showRuleEditDialog(
        context,
        targets: const ['PROXY', 'DEFAULT'],
        isNew: true,
      );
    });
    await open(tester);

    expect(find.text('DEFAULT'), findsOneWidget);
    expect(find.text('PROXY'), findsNothing);
    await tapBarrier(tester);
  });
}
