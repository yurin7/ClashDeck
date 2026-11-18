import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _noNodes = '''
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

const _oneNode = '''
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555

proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - n1
      - DIRECT

rules:
  - MATCH,DEFAULT
''';

Future<EditorState> _pump(
  WidgetTester tester,
  String text, {
  Future<void> Function(String group, String node)? onGroupSelection,
}) async {
  final state = EditorState.fromText(text, fileName: 'demo.yaml');
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProxyBoard(state: state, onGroupSelection: onGroupSelection),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('没有节点时也显示「自动选择」虚拟卡，标「自动测速」且只读', (tester) async {
    await _pump(tester, _noNodes);

    expect(find.text('自动选择'), findsOneWidget);
    expect(find.text('自动测速'), findsOneWidget);
    expect(find.textContaining('还没有节点'), findsOneWidget);

    // 只有真实组卡有「添加成员」/「组设置」，自动选择卡不提供这些入口。
    expect(find.byTooltip('添加成员'), findsOneWidget);
    expect(find.byTooltip('组设置'), findsOneWidget);
  });

  testWidgets('点「自动选择」里的节点只提示、不切换也不写偏好', (tester) async {
    final calls = <String>[];
    await _pump(
      tester,
      _oneNode,
      onGroupSelection: (group, node) async => calls.add('\$group:\$node'),
    );

    final autoCard = find.ancestor(
      of: find.text('自动选择'),
      matching: find.byType(AppCard),
    );
    await tester.tap(
      find.descendant(of: autoCard, matching: find.text('n1')).first,
    );
    await tester.pump();

    expect(find.textContaining('不能手动切'), findsOneWidget);
    expect(calls, isEmpty);
  });

  testWidgets('添加成员面板顶部「内置」段：DIRECT / REJECT / REJECT-DROP（不常用）', (
    tester,
  ) async {
    await _pump(tester, _oneNode);

    await tester.tap(find.byTooltip('添加成员'));
    await tester.pumpAndSettle();

    expect(find.text('内置'), findsOneWidget);
    expect(find.text('REJECT-DROP'), findsOneWidget);
    expect(find.text('不常用'), findsOneWidget);
    // DIRECT 已经在 DEFAULT 里：行还在，只是置灰。
    expect(find.text('已在组内'), findsWidgets);
  });
}
