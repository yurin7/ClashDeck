import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
  - name: n2
    type: vless
    server: b.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - n1
      - n2

rules:
  - MATCH,PROXY
''';

void main() {
  testWidgets('停止状态也能切组内节点：只记偏好，不提示启动内核', (tester) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
    String? pickedGroup;
    String? pickedNode;

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProxyBoard(
            state: state,
            groupSelection: const <String, String>{'PROXY': 'n2'},
            onGroupSelection: (group, node) async {
              pickedGroup = group;
              pickedNode = node;
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // sidecar 里记住的选择显示在组头，并高亮对应芯片。
    // 注意：EditorState 会顺手补一个 DEFAULT 组，所以这里只看 PROXY 的芯片。
    expect(find.textContaining('当前 n2'), findsOneWidget);
    final selected = tester
        .widgetList<NodeChip>(
          find.byWidgetPredicate(
            (widget) => widget is NodeChip && widget.fromGroup == 'PROXY',
          ),
        )
        .where((chip) => chip.selected)
        .map((chip) => chip.node.name)
        .toList();
    expect(selected, ['n2']);

    await tester.tap(
      find.byWidgetPredicate(
        (widget) =>
            widget is NodeChip &&
            widget.fromGroup == 'PROXY' &&
            widget.node.name == 'n1',
      ),
    );
    await tester.pumpAndSettle();

    expect(pickedGroup, 'PROXY');
    expect(pickedNode, 'n1');
    expect(find.textContaining('先启动内核'), findsNothing);
  });

  testWidgets('没有记住选择时回落到组内第一个成员', (tester) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProxyBoard(
            state: state,
            onGroupSelection: (group, node) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final selected = tester
        .widgetList<NodeChip>(
          find.byWidgetPredicate(
            (widget) => widget is NodeChip && widget.fromGroup == 'PROXY',
          ),
        )
        .where((chip) => chip.selected)
        .map((chip) => chip.node.name)
        .toList();
    expect(selected, ['n1']);
    expect(find.textContaining('当前 n1'), findsWidgets);
  });
}
