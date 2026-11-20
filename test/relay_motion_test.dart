import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
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

/// 长按拖起 [from] 到第 [gap] 个间隙（0 表示放到最前）。
Future<TestGesture> _dragToGap(
  WidgetTester tester,
  String from,
  int gap,
) async {
  final gaps = find.byType(DragTarget<Object>);
  final gesture = await tester.startGesture(
    tester.getCenter(find.text(from).first),
  );
  await tester.pump(const Duration(milliseconds: 300));
  await gesture.moveTo(tester.getCenter(gaps.at(gap)));
  await tester.pump(const Duration(milliseconds: 60));
  return gesture;
}

double _x(WidgetTester tester, String name) =>
    tester.getTopLeft(find.text(name).first).dx;

void main() {
  testWidgets('松手后播放淡入过渡，结束后顺序正确', (tester) async {
    await _pumpHost(tester);
    final gesture = await _dragToGap(tester, 'B', 0);
    await gesture.up();

    // 过渡进行中：AnimatedSwitcher 在、也不应该抛异常。
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
    expect(find.byType(AnimatedSwitcher), findsOneWidget);

    await tester.pumpAndSettle();
    expect(_x(tester, 'B'), lessThan(_x(tester, 'A')));
    expect(_x(tester, 'A'), lessThan(_x(tester, 'C')));
  });

  testWidgets('disableAnimations 时一次 pump 即落位', (tester) async {
    await _pumpHost(tester, disableAnimations: true);
    final gesture = await _dragToGap(tester, 'C', 0);
    await gesture.up();

    await tester.pump();
    expect(_x(tester, 'C'), lessThan(_x(tester, 'A')));
    await tester.pumpAndSettle();
  });
}
