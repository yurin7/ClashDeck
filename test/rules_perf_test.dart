import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/rules/rule_row_card.dart';
import 'package:clashdeck/ui/rules_tab.dart';
import 'package:clashdeck/ui/theme.dart';

/// 520 条本地规则：先把「规则多的时候卡」量出来。
///
/// 这里只做**确定性断言**（构建行数、拖拽结果），耗时数字只打印不设阈值，
/// 避免 CI runner 抖动导致假红。
String _yaml(int count) {
  final buffer = StringBuffer()
    ..writeln('mixed-port: 7890')
    ..writeln('proxies: []')
    ..writeln('proxy-groups:')
    ..writeln('  - name: DEFAULT')
    ..writeln('    type: select')
    ..writeln('    proxies:')
    ..writeln('      - DIRECT')
    ..writeln('rules:');
  for (var i = 0; i < count; i++) {
    buffer.writeln('  - DOMAIN-SUFFIX,r$i.com,DIRECT');
  }
  buffer.writeln('  - MATCH,DEFAULT');
  return buffer.toString();
}

const String _small = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
rules:
  - DOMAIN-SUFFIX,a.com,DIRECT
  - DOMAIN-SUFFIX,b.com,DIRECT
  - DOMAIN-SUFFIX,c.com,DIRECT
  - MATCH,DEFAULT
''';

Future<EditorState> _pumpRulesTab(WidgetTester tester, String text) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final state = EditorState.fromText(text, fileName: 't.yaml');
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (_, _) => RulesTab(state: state),
        ),
      ),
    ),
  );
  return state;
}

int _builtRows() =>
    find.byType(RuleRowCard, skipOffstage: false).evaluate().length;

void main() {
  testWidgets('520 条规则：折叠区不建行，展开只建可见行', (tester) async {
    final watch = Stopwatch()..start();
    final state = await _pumpRulesTab(tester, _yaml(519));
    final firstPump = watch.elapsedMilliseconds;

    // 默认展开本地/GEO/正则区，但惰性 sliver 只建可见行。
    final visible = _builtRows();
    expect(visible, lessThanOrEqualTo(40), reason: '展开时不能把 520 行全建出来');

    // 折叠本地区：那批行必须真的不构建（不是 offstage）。
    await tester.tap(find.text('本地精确规则'));
    await tester.pump();
    expect(
      find.text('r0.com', skipOffstage: false),
      findsNothing,
      reason: '折叠区不应该构建行',
    );

    // 再展开，仍然只建可见行。
    watch.reset();
    watch.start();
    await tester.tap(find.text('本地精确规则'));
    await tester.pump();
    final expandPump = watch.elapsedMilliseconds;
    expect(find.text('r0.com', skipOffstage: false), findsOneWidget);
    final expanded = _builtRows();
    expect(expanded, lessThanOrEqualTo(40));

    // 拖一次第一行。
    watch.reset();
    watch.start();
    await tester.drag(
      find.byIcon(Icons.drag_indicator).first,
      const Offset(0, 160),
    );
    await tester.pumpAndSettle();
    final dragPump = watch.elapsedMilliseconds;

    expect(state.profile.rules.length, 520);
    // 只打印，不做阈值断言。
    // ignore: avoid_print
    print(
      'PERF rules=520 firstPump=${firstPump}ms expandPump=${expandPump}ms '
      'dragPump=${dragPump}ms builtVisible=$visible builtExpanded=$expanded',
    );
  });

  testWidgets('拖动排序在本地区内生效', (tester) async {
    final state = await _pumpRulesTab(tester, _small);
    expect(state.profile.rules.first.payload, 'a.com');

    await tester.drag(
      find.byIcon(Icons.drag_indicator).first,
      const Offset(0, 160),
    );
    await tester.pumpAndSettle();

    expect(state.profile.rules.first.payload, isNot('a.com'));
  });

  testWidgets('折叠再展开：规则行还在，顺序不变', (tester) async {
    final state = await _pumpRulesTab(tester, _small);
    await tester.tap(find.text('本地精确规则'));
    await tester.pump();
    expect(find.text('a.com', skipOffstage: false), findsNothing);

    await tester.tap(find.text('本地精确规则'));
    await tester.pump();
    expect(find.text('a.com'), findsOneWidget);
    expect(state.profile.rules.first.payload, 'a.com');
  });
}
