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

Finder _node(String name) => find.byWidgetPredicate(
  (widget) => widget is NodeChip && widget.node.name == name,
);

void main() {
  tearDown(dragState.reset);

  for (final (name, from, forward) in const [('A', 0, true), ('C', 2, false)]) {
    testWidgets('$name 从对应边缘覆盖 B 的 30% 时才预览换位', (tester) async {
      tester.view.physicalSize = const Size(1080, 1400);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final profile = Profile.from(YamlDoc.parse(_relayYaml));
      final group = profile.group('链式')!;
      final moved = <List<int>>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: RelayChain(
              group: group,
              profile: profile,
              delays: const {},
              approx: const {},
              onOpen: (_) {},
              onDelete: (_) {},
              onRemove: (_) {},
              onAddMember: () {},
              onMoveLeft: (_, _) {},
              onMoveRight: (_, _) {},
              onInsertAt: (_, _) {},
              onMoveMember: (from, gap) => moved.add([from, gap]),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final source = tester.getRect(_node(name));
      final target = tester.getRect(_node('B'));
      final touch = tester.getCenter(find.text(name));
      final anchor = touch - source.topLeft;
      final placeholder = find.descendant(
        of: _node(name),
        matching: find.byWidgetPredicate(
          (widget) => widget is CustomPaint && widget.painter != null,
        ),
      );
      final gesture = await tester.startGesture(touch);
      await tester.pump(const Duration(milliseconds: 300));

      Future<void> overlap(double fraction) async {
        final left = forward
            ? target.left + target.width * fraction - source.width
            : target.right - target.width * fraction;
        await gesture.moveTo(Offset(left, target.top) + anchor);
        await tester.pumpAndSettle();
      }

      await overlap(0.29);
      expect(placeholder, findsNothing);
      expect(tester.getRect(_node('B')), target);

      await overlap(0.31);
      expect(placeholder, findsOneWidget);
      expect(tester.getSize(placeholder), source.size);
      expect(
        tester.getTopLeft(_node('B')).dx,
        forward ? lessThan(target.left) : greaterThan(target.left),
      );
      expect(moved, isEmpty);

      await gesture.up();
      await tester.pumpAndSettle();
      expect(moved, [
        [from, forward ? 2 : 1],
      ]);
    });
  }
}
