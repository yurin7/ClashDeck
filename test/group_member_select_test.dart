import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 组里同时有系统策略和普通节点，用来验证「点哪个都能成为当前出口」。
const String _mixed = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    cipher: auto
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
      - REJECT
      - 香港 01
rules:
  - MATCH,DEFAULT
''';

/// 「自动选择」按测速走，成员不能手动点选。
const String _withAuto = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    cipher: auto
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - 香港 01
rules:
  - MATCH,DEFAULT
''';

/// 链式代理：选中的是整条链，卡片不应出现「当前 xxx」。
const String _withRelay = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    cipher: auto
  - name: 日本 02
    type: vless
    server: example.com
    port: 443
    uuid: 22222222-2222-2222-2222-222222222222
    cipher: auto
proxy-groups:
  - name: 链式代理
    type: relay
    proxies:
      - 香港 01
      - 日本 02
rules:
  - MATCH,链式代理
''';

Finder _cardOf(String title) =>
    find.ancestor(of: find.text(title), matching: find.byType(AppCard)).first;

/// 取胶囊外层 Material 的描边色：选中态必须是品牌紫，未选中是中性描边。
Color _borderOf(WidgetTester tester, Finder chip) {
  final shell = find.descendant(of: chip, matching: find.byType(ChipShell));
  final box = tester.widget<AnimatedContainer>(
    find.descendant(of: shell, matching: find.byType(AnimatedContainer)).first,
  );
  final decoration = box.decoration! as BoxDecoration;
  return decoration.border!.top.color;
}

Future<List<String>> _pump(
  WidgetTester tester, {
  String yaml = _mixed,
  Map<String, String> groupSelection = const <String, String>{},
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  final state = EditorState.fromText(yaml, fileName: 't.yaml');
  final calls = <String>[];
  final selection = <String, String>{...groupSelection};
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: StatefulBuilder(
        builder: (context, setLocalState) => Scaffold(
          body: ProxyBoard(
            state: state,
            groupSelection: selection,
            onGroupSelection: (group, name) async {
              calls.add('$group=$name');
              setLocalState(() => selection[group] = name);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return calls;
}

Future<void> _tapMember(WidgetTester tester, Finder card, Finder chip) async {
  await tester.ensureVisible(chip);
  await tester.pumpAndSettle();
  await tester.tap(chip);
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('组内点 DIRECT / REJECT / 节点都能切换当前出口，且只有选中的那个高亮', (tester) async {
    final calls = await _pump(tester);
    final scheme = Theme.of(tester.element(find.byType(ProxyBoard)))
        .colorScheme;
    final card = _cardOf('DEFAULT');
    final direct = find.descendant(
      of: card,
      matching: find.widgetWithText(SystemPolicyChip, 'DIRECT'),
    );
    final reject = find.descendant(
      of: card,
      matching: find.widgetWithText(SystemPolicyChip, 'REJECT'),
    );
    final node = find.descendant(
      of: card,
      matching: find.widgetWithText(NodeChip, '香港 01'),
    );

    // 点 DIRECT：以前这两个系统策略胶囊没接 onTap，点了没反应。
    await _tapMember(tester, card, direct);
    expect(calls, ['DEFAULT=DIRECT']);
    expect(find.text('当前 DIRECT'), findsOneWidget);
    expect(_borderOf(tester, direct), scheme.primary);
    expect(_borderOf(tester, reject), scheme.outlineVariant);

    // 再点 REJECT：选中唯一，DIRECT 退回中性。
    await _tapMember(tester, card, reject);
    expect(calls.last, 'DEFAULT=REJECT');
    expect(find.text('当前 REJECT'), findsOneWidget);
    expect(_borderOf(tester, reject), scheme.primary);
    expect(_borderOf(tester, direct), scheme.outlineVariant);

    // 节点也走同一条回调。
    await _tapMember(tester, card, node);
    expect(calls.last, 'DEFAULT=香港 01');
    expect(find.text('当前 香港 01'), findsOneWidget);
    expect(_borderOf(tester, node), scheme.primary);
    expect(_borderOf(tester, reject), scheme.outlineVariant);
  });

  testWidgets('其它组的系统策略胶囊同样可点（不只 DEFAULT）', (tester) async {
    const yaml = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
    cipher: auto
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
  - name: 手动组
    type: select
    proxies:
      - DIRECT
      - 香港 01
rules:
  - MATCH,DEFAULT
''';
    final calls = await _pump(tester, yaml: yaml);
    final card = _cardOf('手动组');
    final direct = find.descendant(
      of: card,
      matching: find.widgetWithText(SystemPolicyChip, 'DIRECT'),
    );
    await _tapMember(tester, card, direct);
    expect(calls, ['手动组=DIRECT']);
    // DEFAULT 也会回落到首个成员 DIRECT，所以只看这张卡里的「当前」。
    expect(
      find.descendant(of: card, matching: find.text('当前 DIRECT')),
      findsOneWidget,
    );
  });

  testWidgets('「自动选择」的成员不可手动切换', (tester) async {
    final calls = await _pump(tester, yaml: _withAuto);
    final autoCard = _cardOf('自动选择');
    final node = find.descendant(
      of: autoCard,
      matching: find.widgetWithText(NodeChip, '香港 01'),
    );
    await _tapMember(tester, autoCard, node);
    expect(calls, isEmpty);
    expect(
      find.descendant(of: autoCard, matching: find.textContaining('当前 ')),
      findsNothing,
    );
  });

  testWidgets('sidecar 里记着的选择在停止状态也会高亮', (tester) async {
    await _pump(
      tester,
      groupSelection: const <String, String>{'DEFAULT': 'REJECT'},
    );
    final card = _cardOf('DEFAULT');
    final reject = find.descendant(
      of: card,
      matching: find.widgetWithText(SystemPolicyChip, 'REJECT'),
    );
    final scheme = Theme.of(tester.element(find.byType(ProxyBoard)))
        .colorScheme;
    expect(find.text('当前 REJECT'), findsOneWidget);
    expect(_borderOf(tester, reject), scheme.primary);
  });

  testWidgets('链式代理卡不显示「当前 」出口文案', (tester) async {
    await _pump(
      tester,
      yaml: _withRelay,
      groupSelection: const <String, String>{'链式代理': '香港 01'},
    );
    final card = _cardOf('链式代理');
    expect(
      find.descendant(of: card, matching: find.textContaining('当前 ')),
      findsNothing,
    );
    expect(
      find.descendant(of: card, matching: find.textContaining('整链 · 2 阶')),
      findsOneWidget,
    );
  });
}
