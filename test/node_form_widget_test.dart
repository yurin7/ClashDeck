import 'package:clashdeck/ui/node_form_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('新增 vless 节点表单能渲染', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: NodeFormPage()));
    await tester.pumpAndSettle();
    expect(find.text('协议类型'), findsOneWidget);
  });

  testWidgets('编辑已有 vmess 节点表单能渲染', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NodeFormPage(
          initial: const <String, Object?>{
            'name': 'n1',
            'type': 'vmess',
            'server': 'a.com',
            'port': 443,
            'uuid': 'u',
            'cipher': 'auto',
            'network': 'ws',
            'ws-opts': <String, Object?>{'path': '/ws'},
            'ip-version': 'ipv4-prefer',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('协议类型'), findsOneWidget);
  });

  testWidgets('编辑带未知枚举值的节点不崩', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: NodeFormPage(
          initial: const <String, Object?>{
            'name': 'n1',
            'type': 'vless',
            'server': 'a.com',
            'port': 443,
            'uuid': 'u',
            'ip-version': 'some-future-value',
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('协议类型'), findsOneWidget);
  });
}
