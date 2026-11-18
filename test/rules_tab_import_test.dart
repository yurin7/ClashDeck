import 'package:clashdeck/core/edit/rule_presets.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/rules_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 只留一条 MATCH，四个分区都空着，区头才都在首屏。
const _cfg = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,DEFAULT
''';

/// 有多个 select 组时，导入目标也要钉在 DEFAULT 上。
const _cfgTwoGroups = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,PROXY
''';

/// 面板销毁后有 600ms 的控制器释放计时器，测试里要把它走完。
Future<void> _drainDispose(WidgetTester tester) =>
    tester.pump(const Duration(milliseconds: 700));

Future<EditorState> _pumpRulesTab(
  WidgetTester tester, {
  String text = _cfg,
}) async {
  final state = EditorState.fromText(text, fileName: 't.yaml');
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (_, _) => RulesTab(state: state),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

void main() {
  testWidgets('GEO 面板：批量添加写进 DEFAULT，已存在的显示已添加', (tester) async {
    final state = await _pumpRulesTab(tester);

    // 区头顺序：本地 / 在线 / GEO / 兜底，GEO 是第三个「+」。
    await tester.tap(find.byTooltip('添加…').at(2));
    await tester.pumpAndSettle();
    expect(find.text('GEOSITE 离线命中 · 目标统一写入 DEFAULT'), findsOneWidget);

    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 1 条'));
    await tester.pumpAndSettle();
    await _drainDispose(tester);

    expect(
      state.profile.rules.map((rule) => rule.raw),
      contains('GEOSITE,openai,DEFAULT'),
    );
    expect(state.profile.rules.last.isTerminal, isTrue);
    expect(state.lastError, isNull);

    // 再开一次：这条已经在配置里，行置灰、按钮不可点。
    await tester.tap(find.byTooltip('添加…').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    expect(find.text('已添加'), findsOneWidget);
    final addButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '添加 0 条'),
    );
    expect(addButton.onPressed, isNull);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _drainDispose(tester);
  });

  testWidgets('在线面板：勾选计数与全选一致，自定义地址做 http 校验', (tester) async {
    await _pumpRulesTab(tester);
    final total = kLoyalRulesPresets.length + kAclRulesPresets.length;

    await tester.tap(find.byTooltip('添加…').at(1));
    await tester.pumpAndSettle();
    expect(find.text('按整包匹配 · 目标统一写入 DEFAULT'), findsOneWidget);
    expect(find.text('导入 0 个'), findsOneWidget);

    await tester.tap(find.text('全部'));
    await tester.pumpAndSettle();
    expect(find.text('导入 $total 个'), findsOneWidget);

    // 收起两组，露出下面的自定义地址卡片。
    await tester.tap(find.text('Loyalsoldier'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('ACL4SSR'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byType(TextField).first,
      'ftp://example.com/a.txt',
    );
    await tester.tap(find.text('导入这个地址'));
    await tester.pumpAndSettle();
    expect(find.text('地址要以 http:// 或 https:// 开头，且不含空格'), findsOneWidget);

    await tester.tapAt(const Offset(10, 10));
    await tester.pumpAndSettle();
    await _drainDispose(tester);
  });

  testWidgets('粘贴导入：多行规则仍然可用，落库后 MATCH 还在最后', (tester) async {
    final state = await _pumpRulesTab(tester);

    await tester.tap(find.byTooltip('更多操作').first);
    await tester.pumpAndSettle();
    await tester.tap(find.text('粘贴导入…'));
    await tester.pumpAndSettle();
    expect(find.text('导入规则'), findsOneWidget);

    await tester.enterText(
      find.byType(TextField).first,
      'DOMAIN-SUFFIX,a.com,DIRECT\nDOMAIN-SUFFIX,b.com,DIRECT',
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('导入'));
    await tester.pumpAndSettle();

    final raws = state.profile.rules.map((rule) => rule.raw).toList();
    expect(raws, contains('DOMAIN-SUFFIX,a.com,DIRECT'));
    expect(raws, contains('DOMAIN-SUFFIX,b.com,DIRECT'));
    expect(state.profile.rules.last.isTerminal, isTrue);
    expect(state.lastError, isNull);
  });

  testWidgets('导入目标回落到 DEFAULT，不会落进别的 select 组', (tester) async {
    final state = await _pumpRulesTab(tester, text: _cfgTwoGroups);

    await tester.tap(find.byTooltip('添加…').at(2));
    await tester.pumpAndSettle();
    await tester.tap(find.text('AI'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('openai'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('添加 1 条'));
    await tester.pumpAndSettle();
    await _drainDispose(tester);

    final raws = state.profile.rules.map((rule) => rule.raw).toList();
    expect(raws, contains('GEOSITE,openai,DEFAULT'));
    expect(raws, isNot(contains('GEOSITE,openai,PROXY')));
  });
}
