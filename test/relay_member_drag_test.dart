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

void main() {
  testWidgets('链内间隙命中区至少 20 宽，长按拖 A 到 A、B 之间回调 (0,1)', (tester) async {
    tester.view.physicalSize = const Size(1080, 1400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);

    final profile = Profile.from(YamlDoc.parse(_relayYaml));
    final group = profile.group('链式')!;
    final moved = <List<int>>[];

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: RelayChain(
              group: group,
              profile: profile,
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
              onMoveMember: (from, to) => moved.add([from, to]),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 3 个成员 = 首/中/尾三个间隙 + 末尾「加一阶」前的一个间隙。
    final gaps = find.byType(DragTarget<Object>);
    expect(gaps, findsNWidgets(4));
    for (var i = 0; i < 4; i++) {
      expect(
        tester.getSize(gaps.at(i)).width,
        greaterThanOrEqualTo(20),
        reason: '第 $i 个间隙命中区太窄，真机手指落不进去',
      );
    }

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('A').first),
    );
    // 长按 250ms 后才进入拖拽态。
    await tester.pump(const Duration(milliseconds: 300));
    await gesture.moveTo(tester.getCenter(gaps.at(1)));
    await tester.pump(const Duration(milliseconds: 60));
    expect(find.text('A'), findsWidgets, reason: '拖拽浮层应该跟着手指');

    await gesture.up();
    await tester.pumpAndSettle();
    expect(moved, [
      [0, 1],
    ]);
  });
}
