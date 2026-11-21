import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/motion.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/widgets/drag_state.dart';
import 'package:clashdeck/ui/widgets/relay_chain.dart';
import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
proxies:
  - {name: 节点, type: ss, server: a.example.com, port: 443, cipher: aes-128-gcm, password: p}
proxy-groups:
  - {name: 来源, type: select, proxies: [备选, DIRECT]}
  - {name: 目标, type: select, proxies: []}
  - {name: 备选, type: select, proxies: [后备]}
  - {name: 后备, type: select, proxies: [节点]}
  - {name: 自动测速组, type: url-test, proxies: [节点]}
  - {name: 链式组, type: relay, proxies: [节点]}
  - {name: 自动纳入组, type: select, include-all: true}
rules:
  - MATCH,来源
''';

Future<EditorState> _pumpBoard(WidgetTester tester) async {
  final state = EditorState(doc: YamlDoc.parse(_yaml));
  addTearDown(state.dispose);
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: ListenableBuilder(
          listenable: state,
          builder: (context, _) => ProxyBoard(state: state),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return state;
}

Future<TestGesture> _pickUp(WidgetTester tester) async {
  final name = find.descendant(
    of: find.widgetWithText(GroupChip, '备选'),
    matching: find.text('备选'),
  );
  final gesture = await tester.startGesture(tester.getCenter(name));
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpAndSettle();
  expect(dragState.dragging, isTrue);
  return gesture;
}

void main() {
  tearDown(dragState.reset);

  testWidgets('长按显示描述，开始移动时渐隐，落到手动选择组时移动引用', (tester) async {
    final state = await _pumpBoard(tester);
    final tip = find.text('策略组「备选」：组里套组，内核按它的类型再选一次');
    final fade = find.ancestor(of: tip, matching: find.byType(FadeTransition));
    final gesture = await _pickUp(tester);
    expect(tip, findsOneWidget);
    double tooltipOpacity() =>
        tester.widget<FadeTransition>(fade.first).opacity.value;
    expect(tooltipOpacity(), 1);

    await gesture.moveTo(tester.getCenter(find.text('目标')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 36));
    expect(tooltipOpacity(), inExclusiveRange(0, 1));
    await tester.pumpAndSettle();
    expect(tip, findsNothing);
    expect(state.profile.group('来源')!.members, ['备选', 'DIRECT']);

    final nextGroupTitle = find.descendant(
      of: find.byType(SlidableRow),
      matching: find.text('备选'),
    );
    double nextGroupTop() => tester.getTopLeft(nextGroupTitle).dy;
    final beforeDrop = nextGroupTop();
    await gesture.up();
    await tester.pump();
    expect(nextGroupTop(), beforeDrop);
    await tester.pump(Motion.normal.expand ~/ 2);
    final duringDrop = nextGroupTop();
    await tester.pumpAndSettle();
    expect(duringDrop, inExclusiveRange(beforeDrop, nextGroupTop()));
    expect(state.profile.group('来源')!.members, ['DIRECT']);
    expect(state.profile.group('目标')!.members, ['备选']);
    expect(state.profile.group('备选')!.members, ['后备']);
    state.undo();
    expect(state.doc.text, _yaml);
  });

  testWidgets('节点专用组、系统策略和循环引用落点会拒绝策略组胶囊', (tester) async {
    final state = await _pumpBoard(tester);

    for (final target in [
      find.text('自动测速组'),
      find.byType(RelayChain),
      find.text('REJECT'),
      find.text('自动纳入组'),
      find.text('后备').last,
    ]) {
      final gesture = await _pickUp(tester);
      await gesture.moveTo(tester.getCenter(target));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(state.doc.text, _yaml);
      expect(state.canUndo, isFalse);
      expect(dragState.animating, isFalse);
    }
  });

  testWidgets('拖动节点时，可放入与重复的选择组只改变边框颜色', (tester) async {
    final state = await _pumpBoard(tester);
    expect(state.addGroupMember('目标', '节点'), isTrue);
    await tester.pumpAndSettle();

    final scheme = Theme.of(tester.element(find.byType(ProxyBoard)))
        .colorScheme;
    final nodeName = find.descendant(
      of: find.byWidgetPredicate(
        (widget) => widget is NodeChip && widget.fromGroup == '后备',
      ),
      matching: find.text('节点'),
    );
    final gesture = await tester.startGesture(tester.getCenter(nodeName));
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();

    for (final (title, border) in [
      ('来源', scheme.primary),
      ('目标', scheme.error),
    ]) {
      final heading = find.text(title);
      final card = find
          .ancestor(of: heading, matching: find.byType(AppCard))
          .first;
      final idleColor = tester.widget<AppCard>(card).color;
      await gesture.moveTo(tester.getCenter(heading));
      await tester.pump();
      expect(tester.widget<AppCard>(card).borderColor, border);
      expect(tester.widget<AppCard>(card).color, idleColor);
    }

    await gesture.cancel();
    await tester.pumpAndSettle();
  });
}
