import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/rules/group_rules_block.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _cfg = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
      - REJECT
  - name: PROXY
    type: select
    proxies:
      - DIRECT
rules:
  - DOMAIN-SUFFIX,a.com,PROXY
  - MATCH,DEFAULT
''';

void main() {
  Future<EditorState> pumpBlock(
    WidgetTester tester, {
    String target = 'PROXY',
  }) async {
    final state = EditorState.fromText(_cfg, fileName: 't.yaml');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, _) => SingleChildScrollView(
              child: GroupRulesBlock(state: state, target: target),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    return state;
  }

  testWidgets('组规则区块：展开后按 target 列出规则，点开是编辑对话框', (tester) async {
    final state = await pumpBlock(tester);

    expect(find.text('本组规则 1'), findsOneWidget);
    expect(find.text('a.com'), findsNothing);

    await tester.tap(find.text('本组规则 1'));
    await tester.pumpAndSettle();
    expect(find.text('a.com'), findsOneWidget);

    await tester.tap(find.text('a.com'));
    await tester.pumpAndSettle();
    expect(find.text('编辑规则'), findsOneWidget);
    expect(find.text('匹配内容'), findsOneWidget);

    await tester.tapAt(const Offset(8, 8));
    await tester.pumpAndSettle();
    expect(state.profile.rules.first.raw, 'DOMAIN-SUFFIX,a.com,PROXY');
  });

  testWidgets('组规则区块：新建一条落到当前目标，计数随之更新', (tester) async {
    final state = await pumpBlock(tester);

    await tester.tap(find.text('本组规则 1'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建一条'));
    await tester.pumpAndSettle();
    expect(find.text('新建规则'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'b.com');
    await tester.tap(find.text('添加'));
    await tester.pumpAndSettle();

    expect(state.profile.rules.first.raw, 'DOMAIN-SUFFIX,b.com,PROXY');
    expect(find.text('本组规则 2'), findsOneWidget);
  });

  testWidgets('组规则区块：删除走二次确认', (tester) async {
    final state = await pumpBlock(tester);

    await tester.tap(find.text('本组规则 1'));
    await tester.pumpAndSettle();
    await tester.drag(find.text('a.com'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    expect(find.text('删除这条规则？'), findsOneWidget);
    await tester.tap(find.text('删除').last);
    await tester.pumpAndSettle();

    expect(state.profile.rules.length, 1);
    expect(find.text('本组规则 0'), findsOneWidget);
  });

  testWidgets('组规则区块：没有规则时显示空态与入口', (tester) async {
    await pumpBlock(tester, target: 'DIRECT');

    expect(find.text('本组规则 0'), findsOneWidget);
    expect(find.text('还没有规则'), findsOneWidget);
    expect(find.text('添加已有规则'), findsOneWidget);
    expect(find.text('新建一条'), findsOneWidget);
  });
}
