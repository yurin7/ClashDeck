import 'package:clashdeck/ui/rule_edit_dialog.dart';
import 'package:clashdeck/ui/widgets/target_selector_field.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 打开对话框并把 pop 出来的值抓回来。
Future<Object? Function()> _open(
  WidgetTester tester, {
  bool isNew = true,
  String? type,
  String? payload,
  String? target,
  List<String> otherBuiltins = const [],
}) async {
  Object? captured;
  var done = false;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: FilledButton(
              onPressed: () async {
                captured = await showDialog<Object>(
                  context: ctx,
                  builder: (_) => RuleEditDialog(
                    isNew: isNew,
                    initialType: type,
                    initialPayload: payload,
                    initialTarget: target,
                    targets: const ['DIRECT', 'PROXY'],
                    otherBuiltins: otherBuiltins,
                  ),
                );
                done = true;
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
  return () => done ? captured : throw StateError('对话框还没关闭');
}

void main() {
  testWidgets('新建规则：保存返回草稿（类型/内容/目标）', (tester) async {
    final result = await _open(tester);
    expect(find.text('新建规则'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'google.com');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    final draft = result() as RuleDraft;
    expect(draft.type, 'DOMAIN-SUFFIX');
    expect(draft.payload, 'google.com');
    expect(draft.target, 'DIRECT');
    expect(draft.noResolve, isFalse);
  });

  testWidgets('缺匹配内容时不关闭对话框', (tester) async {
    final result = await _open(tester);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    expect(find.text('新建规则'), findsOneWidget);
    expect(result, throwsStateError); // 仍未关闭
  });

  testWidgets('取消返回 null，关闭动画期间不崩', (tester) async {
    final result = await _open(tester);
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(result(), isNull);
    expect(tester.takeException(), isNull);
  });

  testWidgets('编辑已有规则：带删除按钮，GEOIP 有 no-resolve 开关', (tester) async {
    await _open(
      tester,
      isNew: false,
      type: 'GEOIP',
      payload: 'cn',
      target: 'DIRECT',
    );
    expect(find.text('编辑规则'), findsOneWidget);
    expect(find.text('删除'), findsOneWidget);
    expect(find.text('no-resolve'), findsOneWidget);
    expect(find.text('不解析域名（仅 GEOIP / IP-CIDR 生效）'), findsOneWidget);
  });

  testWidgets('删除返回占位值', (tester) async {
    final result = await _open(
      tester,
      isNew: false,
      type: 'GEOIP',
      payload: 'cn',
      target: 'DIRECT',
    );
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(result(), 'delete');
  });

  testWidgets('MATCH 不需要匹配内容', (tester) async {
    final result = await _open(
      tester,
      isNew: false,
      type: 'MATCH',
      target: 'DIRECT',
    );
    expect(find.text('匹配内容'), findsNothing);
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();
    final draft = result() as RuleDraft;
    expect(draft.type, 'MATCH');
    expect(draft.payload, isEmpty);
  });

  testWidgets('编辑规则：高级内置默认折叠，展开后带说明并进目标下拉', (tester) async {
    await _open(
      tester,
      isNew: false,
      type: 'DOMAIN-SUFFIX',
      payload: 'a.com',
      target: 'DIRECT',
      otherBuiltins: const ['PASS', 'GLOBAL'],
    );
    // 目标不再是下拉：点字段打开统一选择面板。
    expect(find.text('高级内置（2）'), findsNothing);
    await tester.tap(find.byType(TargetSelectorField));
    await tester.pumpAndSettle();
    expect(find.text('PASS'), findsNothing);

    await tester.tap(find.text('高级内置（2）'));
    await tester.pumpAndSettle();
    expect(find.text('收起高级内置'), findsOneWidget);
    expect(find.text('PASS'), findsOneWidget);
    expect(find.text('GLOBAL'), findsOneWidget);
    expect(find.text('跳过本条，继续匹配下一条'), findsOneWidget);
    expect(find.text('全局出口组'), findsOneWidget);
    // 系统策略标出来源。
    expect(find.text('系统策略'), findsWidgets);
  });

  testWidgets('新增规则：不渲染高级内置折叠区', (tester) async {
    await _open(tester, otherBuiltins: const ['PASS', 'GLOBAL']);
    await tester.tap(find.byType(TargetSelectorField));
    await tester.pumpAndSettle();
    expect(find.textContaining('高级内置'), findsNothing);
    expect(find.text('PASS'), findsNothing);
  });

  testWidgets('系统策略的目标显示为「系统策略」', (tester) async {
    await _open(tester, target: 'DIRECT');
    await tester.tap(find.byType(TargetSelectorField));
    await tester.pumpAndSettle();
    expect(find.text('系统策略'), findsWidgets);
  });
}
