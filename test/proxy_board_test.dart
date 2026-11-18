import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
proxies:
  - name: 香港 01
    type: vless
    server: hk.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - 自动选择
      - 香港 01
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - 香港 01

rules:
  - MATCH,PROXY
''';

void main() {
  testWidgets('组里套组显示为策略组芯片，不是「未知节点」', (tester) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProxyBoard(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    // 组套组的成员用专属 tooltip 标注，且不再有红色问号
    expect(find.byTooltip('策略组「自动选择」：组里套组，内核按它的类型再选一次'), findsOneWidget);
    expect(find.byIcon(Icons.help_outline), findsNothing);
    // 两个组的卡片都在（"自动选择"既是卡片标题也是 PROXY 的成员芯片）
    expect(find.text('PROXY'), findsOneWidget);
    expect(find.text('自动选择'), findsNWidgets(2));
  });

  testWidgets('内置出站（DIRECT）显示为内置芯片，不是「未知节点」', (tester) async {
    const yaml = '''
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT
      - REJECT
rules:
  - MATCH,PROXY
''';
    final state = EditorState.fromText(yaml, fileName: 'demo.yaml');
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProxyBoard(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    // 迁移会自动补一个 DEFAULT 组（成员含 DIRECT/REJECT），所以内置芯片各出现两次；
    // 系统策略卡卡头还各有一个同图标（size 17），所以总数是 3。
    expect(find.byTooltip('内置出站「DIRECT」：由内核直接处理，不是配置里的节点'), findsNWidgets(2));
    expect(find.byTooltip('内置出站「REJECT」：由内核直接处理，不是配置里的节点'), findsNWidgets(2));
    expect(find.byIcon(Icons.help_outline), findsNothing);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon &&
            widget.icon == Icons.arrow_outward &&
            widget.size == 15,
      ),
      findsNWidgets(2),
    );
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is Icon && widget.icon == Icons.block && widget.size == 15,
      ),
      findsNWidgets(2),
    );
  });
}
