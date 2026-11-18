import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const String _cfg = '''
mixed-port: 7890
proxies:
  - name: n1
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - n1
rules:
  - MATCH,PROXY
''';

class _Board {
  _Board(this.state);

  final EditorState state;

  static Future<_Board> pump(WidgetTester tester, {String text = _cfg}) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(text, fileName: 't.yaml');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProxyBoard(state: state)),
      ),
    );
    await tester.pump();
    return _Board(state);
  }

  Future<void> createGroup(
    WidgetTester tester,
    String name, {
    bool direct = true,
    bool reject = false,
  }) async {
    await tester.ensureVisible(find.text('新建组'));
    await tester.tap(find.text('新建组'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, name);
    if (!direct) {
      await tester.tap(find.text('添加 DIRECT'));
      await tester.pump();
    }
    if (reject) {
      await tester.tap(find.text('添加 REJECT'));
      await tester.pump();
    }
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();
  }
}

void main() {
  testWidgets('新建组入口在节点列表之后、组卡之前', (tester) async {
    await _Board.pump(tester);

    expect(find.text('策略组'), findsOneWidget);
    final button = find.text('新建组');
    expect(button, findsOneWidget);
    expect(
      tester.getTopLeft(button).dy,
      lessThan(tester.getTopLeft(find.text('PROXY')).dy),
    );
  });

  testWidgets('默认勾选 DIRECT：新组初始成员只有 DIRECT', (tester) async {
    final board = await _Board.pump(tester);
    await board.createGroup(tester, '新组');

    expect(board.state.profile.group('新组')?.members, ['DIRECT']);
  });

  testWidgets('取消 DIRECT、勾上 REJECT：新组只写 REJECT', (tester) async {
    final board = await _Board.pump(tester);
    await board.createGroup(tester, '只拒绝', direct: false, reject: true);

    expect(board.state.profile.group('只拒绝')?.members, ['REJECT']);
  });

  testWidgets('两个都不勾不写成员，两个都勾按顺序写入', (tester) async {
    final board = await _Board.pump(tester);

    await board.createGroup(tester, '空组', direct: false);
    expect(board.state.profile.group('空组')?.members, isEmpty);

    await board.createGroup(tester, '都加', reject: true);
    expect(board.state.profile.group('都加')?.members, ['DIRECT', 'REJECT']);
  });
}
