import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/rules/group_rules_block.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const String _yaml = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    cipher: auto
proxy-groups:
  - name: 全直连
    type: select
    proxies:
      - DIRECT
rules:
  - DOMAIN-SUFFIX,example.com,全直连
  - MATCH,DIRECT
''';

Future<EditorState> _pump(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final state = EditorState.fromText(_yaml, fileName: 't.yaml');
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: Scaffold(body: ProxyBoard(state: state)),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

/// 系统策略卡（DIRECT/REJECT）本身只读，但要把规则拖进来改挂。
Finder _systemCard(String policy) => find
    .ancestor(of: find.text('系统策略'), matching: find.byType(AppCard))
    .at(policy == 'DIRECT' ? 0 : 1);

DragTarget<Object> _dragTargetOf(WidgetTester tester, Finder card) =>
    tester.widget<DragTarget<Object>>(
      find
          .ancestor(
            of: card,
            matching: find.byWidgetPredicate((w) => w is DragTarget<Object>),
          )
          .first,
    );

void main() {
  testWidgets('系统策略卡带 DragTarget，可把规则拖到 DIRECT', (tester) async {
    final state = await _pump(tester);
    final rule = state.profile.rules.firstWhere((r) => r.target == '全直连');
    final target = _dragTargetOf(tester, _systemCard('DIRECT'));

    final details = DragTargetDetails<Object>(
      data: RuleDragData(rule),
      offset: Offset.zero,
    );
    expect(target.onWillAcceptWithDetails!(details), isTrue);
    target.onAcceptWithDetails!(details);
    await tester.pumpAndSettle();

    final moved = state.profile.rules.firstWhere((r) => r.index == rule.index);
    expect(moved.target, 'DIRECT');
  });

  testWidgets('规则已挂在目标系统策略时不接受重复拖放', (tester) async {
    final state = await _pump(tester);
    final rule = state.profile.rules.firstWhere((r) => r.target == '全直连');
    final target = _dragTargetOf(tester, _systemCard('DIRECT'));

    final moved = RuleEntry(
      index: rule.index,
      raw: 'DOMAIN-SUFFIX,example.com,DIRECT',
      type: 'DOMAIN-SUFFIX',
      payload: 'example.com',
      target: 'DIRECT',
      options: const [],
    );
    expect(
      target.onWillAcceptWithDetails!(
        DragTargetDetails<Object>(
          data: RuleDragData(moved),
          offset: Offset.zero,
        ),
      ),
      isFalse,
    );
  });
}
