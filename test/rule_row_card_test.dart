import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/ui/rules/rule_row_card.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  Future<void> pumpCard(
    WidgetTester tester, {
    required RuleEntry rule,
    VoidCallback? onTap,
    VoidCallback? onEdit,
    VoidCallback? onMoveToGroup,
    VoidCallback? onRefresh,
    Widget? trailing,
    bool compact = false,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 360,
              child: RuleRowCard(
                rule: rule,
                compact: compact,
                trailing: trailing,
                dragHandle: compact
                    ? null
                    : const Icon(Icons.drag_indicator, size: 17),
                onTap: onTap ?? () {},
                onEdit: onEdit ?? () {},
                onMoveToGroup: onMoveToGroup ?? () {},
                onRefresh: onRefresh,
              ),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('规则行胶囊卡：主标题只放中文名，类型在行尾、目标在第二行', (tester) async {
    var taps = 0;
    final rule = RuleEntry.parse(0, 'RULE-SET,loyal-reject,PROXY');
    await pumpCard(tester, rule: rule, onTap: () => taps++);

    expect(find.text('广告与跟踪域名'), findsOneWidget);
    expect(find.text('RULE-SET'), findsOneWidget);
    expect(find.text('→ PROXY'), findsOneWidget);
    // 拖动手柄复用外部传入的 widget，卡片内部不自建。
    expect(find.byIcon(Icons.drag_indicator), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('广告与跟踪域名'));
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

  testWidgets('规则行胶囊卡：本地规则直接用匹配内容当标题', (tester) async {
    final rule = RuleEntry.parse(0, 'DOMAIN-SUFFIX,google.com,PROXY');
    await pumpCard(tester, rule: rule);

    expect(find.text('google.com'), findsOneWidget);
    expect(find.text('DOMAIN-SUFFIX'), findsOneWidget);
    expect(find.text('→ PROXY'), findsOneWidget);
  });

  testWidgets('规则行胶囊卡：没有保存/取消/删除按钮，删除只走左滑', (tester) async {
    final rule = RuleEntry.parse(0, 'DOMAIN-SUFFIX,google.com,PROXY');
    await pumpCard(tester, rule: rule);

    expect(find.text('保存'), findsNothing);
    expect(find.text('取消'), findsNothing);
    expect(find.text('删除'), findsNothing);
    expect(find.byTooltip('更多操作'), findsNothing);
  });

  testWidgets('规则行胶囊卡：行尾刷新按钮触发 onRefresh，不点整行', (tester) async {
    var refreshes = 0;
    var taps = 0;
    final rule = RuleEntry.parse(0, 'RULE-SET,loyal-reject,PROXY');
    await pumpCard(
      tester,
      rule: rule,
      trailing: const Text('未缓存'),
      onRefresh: () => refreshes++,
      onTap: () => taps++,
    );

    expect(find.text('未缓存'), findsOneWidget);
    await tester.tap(find.byTooltip('更新规则集'));
    await tester.pump();
    expect(refreshes, 1);
    expect(taps, 0);
  });

  testWidgets('规则行胶囊卡：换组图标触发 onMoveToGroup，不点整行', (tester) async {
    var moves = 0;
    var taps = 0;
    final rule = RuleEntry.parse(0, 'DOMAIN-SUFFIX,google.com,PROXY');
    await pumpCard(
      tester,
      rule: rule,
      onMoveToGroup: () => moves++,
      onTap: () => taps++,
    );

    expect(find.byIcon(Icons.swap_horiz), findsOneWidget);
    await tester.tap(find.byTooltip('换到别的组'));
    await tester.pump();
    expect(moves, 1);
    expect(taps, 0);
  });

  testWidgets('规则行胶囊卡：紧凑模式只留色条 + 标题', (tester) async {
    final rule = RuleEntry.parse(0, 'DOMAIN-SUFFIX,google.com,PROXY');
    await pumpCard(tester, rule: rule, compact: true);

    expect(find.text('google.com'), findsOneWidget);
    expect(find.byIcon(Icons.chevron_right), findsNothing);
    expect(find.byIcon(Icons.drag_indicator), findsNothing);
    expect(find.text('DOMAIN-SUFFIX'), findsNothing);
    expect(find.byIcon(Icons.swap_horiz), findsNothing);
  });
}
