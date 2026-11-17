import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/ui/rules/rule_row_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required RuleEntry rule,
    String? note,
    VoidCallback? onTap,
    VoidCallback? onEdit,
    VoidCallback? onMoveToGroup,
    VoidCallback? onDelete,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: RuleRowCard(
                rule: rule,
                note: note,
                dragHandle: const Icon(Icons.drag_indicator, size: 17),
                onTap: onTap ?? () {},
                onEdit: onEdit ?? () {},
                onMoveToGroup: onMoveToGroup ?? () {},
                onDelete: onDelete ?? () {},
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('规则行胶囊卡：类型 + 匹配内容 + → 目标，并保留拖动手柄', (tester) async {
    var taps = 0;
    final rule = RuleEntry.parse(0, 'RULE-SET,loyal-reject,PROXY');
    await pumpCard(tester, rule: rule, note: '广告与跟踪域名', onTap: () => taps++);

    expect(find.text('RULE-SET'), findsOneWidget);
    expect(find.text('loyal-reject'), findsOneWidget);
    expect(find.text('→ PROXY  ·  广告与跟踪域名'), findsOneWidget);
    // 拖动手柄复用外部传入的 widget，卡片内部不自建。
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('loyal-reject'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('规则行胶囊卡：兜底规则显示「所有未匹配流量」', (tester) async {
    final rule = RuleEntry.parse(1, 'MATCH,DIRECT');
    await pumpCard(tester, rule: rule);

    expect(find.text('MATCH'), findsOneWidget);
    expect(find.text('所有未匹配流量'), findsOneWidget);
    expect(find.text('兜底'), findsOneWidget);
    expect(find.text('→ DIRECT'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('规则行胶囊卡：⋮ 菜单提供编辑 / 改挂到组 / 删除', (tester) async {
    var edits = 0;
    var moves = 0;
    var deletes = 0;
    final rule = RuleEntry.parse(0, 'DOMAIN-SUFFIX,google.com,PROXY');
    await pumpCard(
      tester,
      rule: rule,
      onEdit: () => edits++,
      onMoveToGroup: () => moves++,
      onDelete: () => deletes++,
    );

    await tester.tap(find.byTooltip('更多操作'));
    await tester.pumpAndSettle();
    expect(find.text('编辑'), findsOneWidget);
    expect(find.text('改挂到组'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(deletes, 1);
    expect(edits, 0);
    expect(moves, 0);
  });
}
