import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/rules_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('规则 Tab：添加规则插到 MATCH 之前', (tester) async {
    final state = EditorState.fromText(
      ProfileStore.starterConfig(name: 't'),
      fileName: 't.yaml',
    );
    expect(state.profile.rules.length, 2);
    expect(state.profile.rules.last.isTerminal, isTrue);

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

    await tester.tap(find.text('添加规则'));
    await tester.pumpAndSettle();
    expect(find.text('新建规则'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'google.com');
    await tester.pumpAndSettle();
    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(state.lastError, isNull);
    expect(state.profile.rules.length, 3);
    // 新增规则按分区插到「本地精确规则」区首位，旧的 GEOIP 往后站。
    expect(state.profile.rules[0].type, 'DOMAIN-SUFFIX');
    expect(state.profile.rules[0].payload, 'google.com');
    expect(state.profile.rules.last.isTerminal, isTrue);
  });
}
