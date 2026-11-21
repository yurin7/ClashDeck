import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/widgets/drag_state.dart';
import 'package:clashdeck/ui/widgets/relay_chain.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _relayYaml = '''
mixed-port: 7890
proxies:
  - {name: A, type: ss, server: a.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: B, type: ss, server: b.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: C, type: ss, server: c.example.com, port: 443, cipher: aes-128-gcm, password: p}
proxy-groups:
  - name: 链式
    type: relay
    proxies: [A, B, C]
rules:
  - MATCH,链式
''';

/// 拖放后真的重排成员，用来验证落位过渡与最终顺序。
class _ReorderHost extends StatefulWidget {
  const _ReorderHost({required this.profile, this.disableAnimations = false});

  final Profile profile;
  final bool disableAnimations;

  @override
  State<_ReorderHost> createState() => _ReorderHostState();
}

class _ReorderHostState extends State<_ReorderHost> {
  List<String> _members = const ['A', 'B', 'C'];

  GroupEntry get _group => GroupEntry(
    index: 0,
    name: '链式',
    type: 'relay',
    members: List<String>.unmodifiable(_members),
    raw: <String, Object?>{'name': '链式', 'type': 'relay', 'proxies': _members},
  );

  void _move(int from, int to) {
    final next = [..._members];
    final item = next.removeAt(from);
    next.insert(from < to ? to - 1 : to, item);
    setState(() => _members = next);
  }

  @override
  Widget build(BuildContext context) {
    final chain = RelayChain(
      group: _group,
      profile: widget.profile,
      delays: const {},
      approx: const {},
      onOpen: (_) {},
      onDelete: (_) {},
      onRemove: (_) {},
      onSelect: (_) {},
      onAddMember: () {},
      onMoveLeft: (_, _) {},
      onMoveRight: (_, _) {},
      onInsertAt: (_, _) {},
      onMoveMember: _move,
    );
    return MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(
          size: const Size(420, 800),
          disableAnimations: widget.disableAnimations,
        ),
        child: Scaffold(body: SingleChildScrollView(child: chain)),
      ),
    );
  }
}

Future<void> _pumpHost(
  WidgetTester tester, {
  bool disableAnimations = false,
}) async {
  tester.view.physicalSize = const Size(1080, 1600);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    _ReorderHost(
      profile: Profile.from(YamlDoc.parse(_relayYaml)),
      disableAnimations: disableAnimations,
    ),
  );
  await tester.pumpAndSettle();
}

Finder _node(String name) => find.byWidgetPredicate(
  (widget) => widget is NodeChip && widget.node.name == name,
);

Future<TestGesture> _dragCOverA(WidgetTester tester) async {
  final source = tester.getRect(_node('C'));
  final target = tester.getRect(_node('A'));
  final touch = tester.getCenter(find.text('C'));
  final anchor = touch - source.topLeft;
  final gesture = await tester.startGesture(touch);
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.moveTo(
    Offset(target.right - target.width * 0.35, target.top) + anchor,
  );
  await tester.pumpAndSettle();
  return gesture;
}

List<String> _members(WidgetTester tester) =>
    tester.widget<RelayChain>(find.byType(RelayChain)).group.members;

void main() {
  tearDown(dragState.reset);

  testWidgets('松手前预览新位置，松手后从浮层滑入占位框', (tester) async {
    await _pumpHost(tester);
    final gesture = await _dragCOverA(tester);
    expect(_members(tester), ['A', 'B', 'C']);

    final floating = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is Opacity && widget.opacity == 0.92,
      ),
      matching: find.text('C'),
    );
    final releasePosition = tester.getTopLeft(floating);
    final slot = tester.getTopLeft(_node('C'));
    final adjacent = tester.getTopLeft(_node('A'));
    expect(slot.dx, lessThan(adjacent.dx));

    await gesture.up();
    await tester.pump();
    expect(_members(tester), ['C', 'A', 'B']);
    expect(
      (tester.getTopLeft(find.text('C')) - releasePosition).distance,
      lessThan(0.01),
    );

    await tester.pump(const Duration(milliseconds: 100));
    final halfway = tester.getTopLeft(find.text('C'));
    await tester.pump(const Duration(milliseconds: 100));

    final finalLabel = tester.getTopLeft(find.text('C'));
    expect(
      (halfway - releasePosition).distance,
      inExclusiveRange(0, (finalLabel - releasePosition).distance),
    );
    expect(tester.getTopLeft(_node('C')), slot);
    expect(tester.getTopLeft(_node('A')), adjacent);
  });

  testWidgets('关闭动画时松手即提交预览顺序', (tester) async {
    await _pumpHost(tester, disableAnimations: true);
    final gesture = await _dragCOverA(tester);
    final slot = tester.getTopLeft(_node('C'));
    await gesture.up();
    await tester.pump();
    expect(_members(tester), ['C', 'A', 'B']);
    expect(tester.getTopLeft(_node('C')), slot);
  });
}
