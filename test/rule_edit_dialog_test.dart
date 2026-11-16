import 'package:clashdeck/ui/rule_edit_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 打开对话框并把 pop 出来的值抓回来。
Future<Object? Function()> _open(
  WidgetTester tester, {
  bool isNew = true,
  String? type,
  String? payload,
  String? target,
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
    expect(find.text('no-resolve（不解析域名）'), findsOneWidget);
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
}
