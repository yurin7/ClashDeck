import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/rules/rule_row_card.dart';
import 'package:clashdeck/ui/rules_tab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('规则左滑删除：取消后行保持收起、规则不变', (tester) async {
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(
      ProfileStore.starterConfig(name: 't'),
      fileName: 't.yaml',
    );
    final before = state.profile.rules.length;

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

    final row = find.byType(RuleRowCard).first;
    await tester.drag(row, const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(find.textContaining('删除这条规则？'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(find.text('删除'), findsNothing, reason: '取消后要保持收起');
    expect(state.profile.rules.length, before);
  });
}
