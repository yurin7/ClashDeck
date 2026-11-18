import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/rule_picker_sheet.dart';
import 'package:clashdeck/ui/sheets/node_picker_sheet.dart';
import 'package:clashdeck/ui/sheets/picker_sheet.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets/selectable_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: 1.2.3.4
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - 香港 01
      - DIRECT
      - REJECT
rules:
  - DOMAIN-SUFFIX,a.com,DIRECT
  - MATCH,DEFAULT
''';

void main() {
  testWidgets('节点面板与规则面板共用同一个骨架和行样式', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(_yaml, fileName: 't.yaml');
    final profile = state.profile;

    Future<void> open(Future<void> Function(BuildContext) show) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ClashDeckTheme.dark(),
          home: Scaffold(
            body: Builder(
              builder: (context) => Center(
                child: FilledButton(
                  onPressed: () => show(context),
                  child: const Text('打开'),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.tap(find.text('打开'));
      await tester.pumpAndSettle();
    }

    Future<void> close() async {
      await tester.tap(find.text('取消'));
      await tester.pumpAndSettle();
    }

    await open(
      (context) => showNodePickerSheet(
        context,
        profile: profile,
        groupName: 'DEFAULT',
        members: const <String>[],
      ),
    );
    expect(find.byType(PickerSheetScaffold), findsOneWidget);
    expect(find.byType(SelectableTile), findsWidgets);
    final nodeTile = tester.widget<SelectableTile>(
      find.byType(SelectableTile).first,
    );
    final nodeRadius = _tileRadius(tester, find.byType(SelectableTile).first);
    await close();

    await open(
      (context) => showRulePickerSheet(
        context,
        group: 'DEFAULT',
        candidates: rulesAssignableTo(profile, 'DEFAULT'),
      ),
    );
    expect(find.byType(PickerSheetScaffold), findsOneWidget);
    expect(find.byType(SelectableTile), findsWidgets);
    final ruleTile = tester.widget<SelectableTile>(
      find.byType(SelectableTile).first,
    );
    final ruleRadius = _tileRadius(tester, find.byType(SelectableTile).first);

    // 行高随内容变化（节点是单行 chip，规则是 chip + 副标题），但骨架一致：
    // 同一个 SelectableTile、同样的内边距与圆角。
    expect(ruleTile.padding, nodeTile.padding);
    expect(ruleRadius, nodeRadius);
  });

  testWidgets('选中态是整行高亮（没有 Checkbox）', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(_yaml, fileName: 't.yaml');
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showNodePickerSheet(
                  context,
                  profile: state.profile,
                  groupName: 'DEFAULT',
                  members: const <String>[],
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNothing);

    final row = find.ancestor(
      of: find.text('香港 01'),
      matching: find.byType(SelectableTile),
    );
    await tester.ensureVisible(row);
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pump();

    expect(
      tester.widget<SelectableTile>(row).selected,
      isTrue,
      reason: '选中行应当高亮',
    );
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.text('加入 1 个'), findsOneWidget);
  });
}

double? _tileRadius(WidgetTester tester, Finder tile) {
  final material = tester.widget<Material>(
    find.descendant(of: tile, matching: find.byType(Material)).first,
  );
  final shape = material.shape;
  if (shape is! RoundedRectangleBorder) return null;
  final radius = shape.borderRadius;
  if (radius is! BorderRadius) return null;
  return radius.topLeft.x;
}
