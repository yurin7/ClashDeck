import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';

const _yaml = '''
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 1, cipher: aes-128-gcm, password: x}
  - {name: b, type: ss, server: 1.1.1.1, port: 2, cipher: aes-128-gcm, password: x}
  - {name: c, type: ss, server: 1.1.1.1, port: 3, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: chain, type: relay, proxies: [a, b, c]}
rules:
  - MATCH,chain
''';

void main() {
  testWidgets('策略组里的链式代理：点「加一阶」弹出节点选择面板', (tester) async {
    final state = EditorState(doc: YamlDoc.parse(_yaml));
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 900, child: ProxyBoard(state: state)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final addLink = find.text('加一阶');
    await tester.ensureVisible(addLink);
    await tester.pumpAndSettle();
    await tester.tap(addLink);
    await tester.pumpAndSettle();

    expect(find.text('选择要加入的节点'), findsOneWidget);
  });
}
