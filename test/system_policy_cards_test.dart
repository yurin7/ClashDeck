import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
proxies: []

proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
      - REJECT

rules:
  - MATCH,DEFAULT
''';

Future<EditorState> _pump(WidgetTester tester) async {
  final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: ProxyBoard(state: state)),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('系统策略区：两张只读卡，标「系统策略」，不能改名/删组', (tester) async {
    await _pump(tester);

    // 分区标题 + 两张卡上的 Pill。
    expect(find.text('系统策略'), findsNWidgets(3));
    expect(find.text('DIRECT'), findsWidgets);
    expect(find.text('REJECT'), findsWidgets);
    expect(find.text('直连：不经过代理，直接访问目标'), findsOneWidget);
    expect(find.text('拒绝：直接断开，不发出请求'), findsOneWidget);

    // 只有真实组卡有「组设置」菜单，系统策略卡没有。
    expect(find.byTooltip('组设置'), findsOneWidget);
    // 系统策略卡上没有「添加成员」入口。
    expect(find.byTooltip('添加成员'), findsOneWidget);
  });

  testWidgets('系统策略卡能挂规则：新建后落在该策略下，计数 +1', (tester) async {
    final state = await _pump(tester);

    expect(find.text('添加规则'), findsNWidgets(2));
    await tester.tap(find.text('添加规则').first);
    await tester.pumpAndSettle();
    expect(find.text('新建规则'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'a.com');
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(
      state.profile.rules.map((r) => r.raw),
      contains('DOMAIN-SUFFIX,a.com,DIRECT'),
    );
    expect(state.profile.rules.last.isTerminal, isTrue);
    // DEFAULT 组卡里 MATCH 记 1 条，DIRECT 卡里新规则也记 1 条。
    expect(find.text('本组规则 1'), findsNWidgets(2));
    expect(find.text('本组规则 0'), findsOneWidget); // REJECT 卡还是空的
  });
}
