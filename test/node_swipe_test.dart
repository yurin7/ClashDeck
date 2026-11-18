import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets/node_row.dart';

const String _yaml = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: a.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
  - name: 日本 02
    type: vmess
    server: b.example.com
    port: 443
    uuid: 22222222-3333-4444-5555-666666666666
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - 香港 01
      - 日本 02
      - DIRECT
rules:
  - MATCH,PROXY
''';

Future<EditorState> _pumpBoard(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final state = EditorState.fromText(_yaml, fileName: 't.yaml');
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: Scaffold(body: ProxyBoard(state: state)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return state;
}

Future<void> _expandNodes(WidgetTester tester) async {
  await tester.tap(find.text('节点列表'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

void main() {
  testWidgets('节点左滑删除：提示引用组，取消后保持收起且节点还在', (tester) async {
    final state = await _pumpBoard(tester);
    await _expandNodes(tester);

    final row = find.byKey(const ValueKey('node-row-香港 01'));
    await tester.ensureVisible(row);
    await tester.drag(row, const Offset(-120, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除节点「香港 01」？'), findsOneWidget);
    expect(find.textContaining('个组引用了它：DEFAULT、PROXY'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('删除'), findsNothing, reason: '取消后行保持收起');
    expect(state.profile.proxyByName['香港 01'], isNotNull);
  });

  testWidgets('节点行单行互斥：滑开第二行时第一行收起', (tester) async {
    await _pumpBoard(tester);
    await _expandNodes(tester);

    final first = find.byKey(const ValueKey('node-row-香港 01'));
    final second = find.byKey(const ValueKey('node-row-日本 02'));
    await tester.ensureVisible(first);

    await tester.drag(first, const Offset(-120, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除'), findsOneWidget);

    await tester.drag(second, const Offset(-120, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('删除'), findsOneWidget, reason: '同一时刻只有一行展开');
  });

  testWidgets('点行进入编辑；长按拖拽不误触编辑', (tester) async {
    await _pumpBoard(tester);
    await _expandNodes(tester);

    await tester.tap(
      find.descendant(
        of: find.byKey(const ValueKey('node-row-日本 02')),
        matching: find.text('日本 02'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('编辑节点'), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();

    final gesture = await tester.startGesture(
      tester.getCenter(
        find.descendant(
          of: find.byKey(const ValueKey('node-row-日本 02')),
          matching: find.text('日本 02'),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(find.text('编辑节点'), findsNothing);
    expect(find.byType(NodeRow), findsNWidgets(2));
  });
}
