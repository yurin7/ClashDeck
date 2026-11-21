import 'package:clashdeck/runtime/mihomo_api.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
  - name: n2
    type: vless
    server: b.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - n1
      - n2

rules:
  - MATCH,PROXY
''';

class _SelectionApi extends Fake implements MihomoApi {
  final selections = <String>[];

  @override
  Future<void> selectProxy(String group, String name) async {
    selections.add('$group/$name');
  }

  @override
  void close() {}
}

Finder _groupChip(String name) => find.byWidgetPredicate(
  (widget) =>
      widget is NodeChip &&
      widget.fromGroup == 'PROXY' &&
      widget.node.name == name,
);

Future<Map<String, String>> _pumpBoard(
  WidgetTester tester,
  EditorState state, {
  RuntimeController? runtime,
  bool isActiveProfile = true,
  Map<String, String> saved = const {},
}) async {
  final selection = {...saved};
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: StatefulBuilder(
          builder: (context, setState) => ProxyBoard(
            state: state,
            runtime: runtime,
            isActiveProfile: isActiveProfile,
            groupSelection: selection,
            onGroupSelection: (group, node) async {
              setState(() => selection[group] = node);
            },
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return selection;
}

void main() {
  testWidgets('内核停下后，点按仍保存并高亮新节点', (tester) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
    final api = _SelectionApi();
    final runtime = RuntimeController(
      configProvider: () => state.doc,
      apiOverride: api,
    );
    addTearDown(runtime.dispose);
    runtime.debugSetPhase(RuntimePhase.running);
    expect(await runtime.selectNode('PROXY', 'n2'), isTrue);
    await runtime.applyStatus({'running': false, 'kernelState': 'stopped'});
    expect(runtime.phase, RuntimePhase.idle);

    final saved = await _pumpBoard(
      tester,
      state,
      runtime: runtime,
      saved: {'PROXY': 'n2'},
    );

    expect(find.textContaining('当前 n2'), findsOneWidget);
    expect(tester.widget<NodeChip>(_groupChip('n2')).selected, isTrue);

    await tester.tap(_groupChip('n1'));
    await tester.pumpAndSettle();

    expect(saved, {'PROXY': 'n1'});
    expect(api.selections, ['PROXY/n2']);
    expect(tester.widget<NodeChip>(_groupChip('n1')).selected, isTrue);
    expect(tester.widget<NodeChip>(_groupChip('n2')).selected, isFalse);
    expect(find.textContaining('当前 n1'), findsWidgets);
    expect(find.textContaining('先启动内核'), findsNothing);
  });

  testWidgets('运行配置采用有效的实时出口，过期出口回落到保存的节点', (tester) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
    final api = _SelectionApi();
    final runtime = RuntimeController(
      configProvider: () => state.doc,
      apiOverride: api,
    );
    addTearDown(runtime.dispose);
    runtime.debugSetPhase(RuntimePhase.running);
    expect(await runtime.selectNode('PROXY', 'n1'), isTrue);

    final saved = await _pumpBoard(
      tester,
      state,
      runtime: runtime,
      saved: {'PROXY': 'n2'},
    );
    expect(tester.widget<NodeChip>(_groupChip('n1')).selected, isTrue);

    expect(await runtime.selectNode('PROXY', '已移除节点'), isTrue);
    await tester.pumpAndSettle();
    expect(tester.widget<NodeChip>(_groupChip('n2')).selected, isTrue);

    await tester.tap(_groupChip('n1'));
    await tester.pumpAndSettle();
    expect(saved, {'PROXY': 'n1'});
    expect(runtime.selected, {'PROXY': 'n1'});
    expect(api.selections.last, 'PROXY/n1');
    expect(tester.widget<NodeChip>(_groupChip('n1')).selected, isTrue);
  });

  testWidgets('编辑其他配置时，点按只更新该配置的组内选择', (tester) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
    final api = _SelectionApi();
    final runtime = RuntimeController(
      configProvider: () => state.doc,
      apiOverride: api,
    );
    addTearDown(runtime.dispose);
    runtime.debugSetPhase(RuntimePhase.running);
    expect(await runtime.selectNode('PROXY', 'n2'), isTrue);

    final saved = await _pumpBoard(
      tester,
      state,
      runtime: runtime,
      isActiveProfile: false,
      saved: {'PROXY': 'n2'},
    );
    await tester.tap(_groupChip('n1'));
    await tester.pumpAndSettle();

    expect(saved, {'PROXY': 'n1'});
    expect(runtime.selected, {'PROXY': 'n2'});
    expect(api.selections, ['PROXY/n2']);
    expect(tester.widget<NodeChip>(_groupChip('n1')).selected, isTrue);
    expect(tester.widget<NodeChip>(_groupChip('n2')).selected, isFalse);
  });

  testWidgets('没有记住选择时回落到组内第一个成员', (tester) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
    await _pumpBoard(tester, state);

    expect(tester.widget<NodeChip>(_groupChip('n1')).selected, isTrue);
    expect(tester.widget<NodeChip>(_groupChip('n2')).selected, isFalse);
    expect(find.textContaining('当前 n1'), findsWidgets);
  });
}
