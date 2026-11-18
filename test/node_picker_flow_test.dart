import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/sheets/picker_sheet.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _noNodes = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - REJECT
rules:
  - MATCH,PROXY
''';

const _oneNode = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: 1.2.3.4
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - 香港 01
rules:
  - MATCH,PROXY
''';

void main() {
  testWidgets('0 个节点也能把系统策略加进组：DIRECT 可选、可提交、写进 proxies', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(_noNodes, fileName: 't.yaml');
    await _pump(tester, state);

    // 第二个「添加成员」是 PROXY 组（DEFAULT 由迁移自动补在最前面）。
    await tester.tap(find.byTooltip('添加成员').at(1));
    await tester.pumpAndSettle();

    expect(find.byType(Checkbox), findsNothing);
    expect(find.text('系统策略'), findsWidgets);

    // REJECT 已在 PROXY 里 → 置灰不可选；DIRECT 不在 → 可选。
    expect(find.text('已在组内'), findsOneWidget);
    await tester.tap(_sheetText('DIRECT'));
    await tester.pump();
    expect(find.text('已选 1'), findsOneWidget);

    await tester.tap(find.text('加入 1 个'));
    await tester.pumpAndSettle();

    expect(state.profile.group('PROXY')!.members, contains('DIRECT'));
    // 组卡上也画出了 DIRECT（系统策略 chip），不再是未知节点。
    expect(
      find.byWidgetPredicate(
        (w) => w is SystemPolicyChip && w.name == 'DIRECT',
      ),
      findsWidgets,
    );
  });

  testWidgets('系统策略行可以来回切换：再点一次取消，按钮跟着禁用', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(_noNodes, fileName: 't.yaml');
    await _pump(tester, state);

    await tester.tap(find.byTooltip('添加成员').at(1));
    await tester.pumpAndSettle();

    await tester.tap(_sheetText('DIRECT'));
    await tester.pump();
    expect(find.text('已选 1'), findsOneWidget);
    expect(find.text('加入 1 个'), findsOneWidget);

    await tester.tap(_sheetText('DIRECT'));
    await tester.pump();
    expect(find.text('已选 0'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.text('加入 0 个'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull, reason: '没选任何东西时提交按钮应当禁用');
  });

  testWidgets('新建组默认把第一个成员设为当前出口（DIRECT），组卡高亮', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(_oneNode, fileName: 't.yaml');
    final calls = <(String, String)>[];
    var selection = <String, String>{};
    late StateSetter setBoard;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              setBoard = setState;
              return ProxyBoard(
                state: state,
                groupSelection: selection,
                onGroupSelection: (group, node) async {
                  calls.add((group, node));
                  setBoard(() => selection = {...selection, group: node});
                },
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('新建组'));
    await tester.tap(find.text('新建组'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, '测试组');
    await tester.tap(find.text('创建'));
    await tester.pumpAndSettle();

    expect(calls, <(String, String)>[('测试组', 'DIRECT')]);
    expect(state.profile.group('测试组')!.members, <String>['DIRECT']);
    expect(
      find.byWidgetPredicate(
        (w) => w is SystemPolicyChip && w.name == 'DIRECT' && w.selected,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('当前 DIRECT'), findsOneWidget);
  });

  testWidgets('新配置 DEFAULT 里的 DIRECT 会按 sidecar 的选择高亮', (tester) async {
    tester.view.physicalSize = const Size(1080, 4800);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final state = EditorState.fromText(_noNodes, fileName: 't.yaml');
    await _pump(tester, state, selection: const {'DEFAULT': 'DIRECT'});

    expect(
      find.byWidgetPredicate(
        (w) => w is SystemPolicyChip && w.name == 'DIRECT' && w.selected,
      ),
      findsOneWidget,
    );
    expect(find.textContaining('当前 DIRECT'), findsOneWidget);
  });
}

Future<void> _pump(
  WidgetTester tester,
  EditorState state, {
  Map<String, String> selection = const {},
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ProxyBoard(state: state, groupSelection: selection),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder _sheetText(String text) => find.descendant(
  of: find.byType(PickerSheetScaffold),
  matching: find.text(text),
);
