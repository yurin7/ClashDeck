import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/ui/widgets/pulse_swipe.dart';

void main() {
  late AnimationController reveal;
  late List<int> pageChanges;
  late int openCalls;
  late bool? settled;

  Widget build({int index = 0}) {
    return MaterialApp(
      home: Scaffold(
        body: PulseSwipeArea(
          index: index,
          pageCount: 3,
          reveal: reveal,
          onOpenPulse: () => openCalls++,
          onSettle: (open) => settled = open,
          onPageChange: pageChanges.add,
          child: const SizedBox.expand(child: ColoredBox(color: Colors.black)),
        ),
      ),
    );
  }

  setUp(() {
    pageChanges = <int>[];
    openCalls = 0;
    settled = null;
  });

  testWidgets('遮罩半开时左拖只回收进度，不换页', (tester) async {
    reveal = AnimationController(vsync: const TestVSync());
    addTearDown(reveal.dispose);
    reveal.value = 0.4;
    await tester.pumpWidget(build());
    final g = await tester.startGesture(const Offset(700, 400));
    await g.moveBy(const Offset(-240, 0));
    await tester.pump();
    expect(reveal.value, lessThan(0.4));
    await g.up();
    await tester.pump();
    expect(pageChanges, isEmpty);
    expect(settled, isFalse);
  });

  testWidgets('关闭态左拖超过阈值切到下一页', (tester) async {
    reveal = AnimationController(vsync: const TestVSync());
    addTearDown(reveal.dispose);
    await tester.pumpWidget(build());
    final g = await tester.startGesture(const Offset(700, 400));
    await g.moveBy(const Offset(-400, 0));
    await g.up();
    await tester.pump();
    expect(pageChanges, [1]);
    expect(openCalls, 0);
  });

  testWidgets('首页右拖拉出抽屉且不换页', (tester) async {
    reveal = AnimationController(vsync: const TestVSync());
    addTearDown(reveal.dispose);
    await tester.pumpWidget(build());
    final g = await tester.startGesture(const Offset(400, 400));
    await g.moveBy(const Offset(200, 0));
    await g.up();
    await tester.pump();
    expect(openCalls, 1);
    expect(reveal.value, greaterThan(0));
    expect(pageChanges, isEmpty);
  });

  testWidgets('拖到一半反向松开，不跳页', (tester) async {
    reveal = AnimationController(vsync: const TestVSync());
    addTearDown(reveal.dispose);
    await tester.pumpWidget(build());
    final g = await tester.startGesture(const Offset(800, 400));
    await g.moveBy(const Offset(-300, 0));
    await g.moveBy(const Offset(280, 0));
    await g.up();
    await tester.pump();
    expect(pageChanges, isEmpty);
  });
}
