import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/pulse_entry.dart';

/// 负一屏入口：概览（PageView 第一页）继续向右拖出 overscroll 才触发。
///
/// 0.3.0 的 bug 是入口写在概览页里的 `onHorizontalDrag*`，被 PageView 的
/// 横向手势竞技场吃掉，左右滑都打不开；现在改为监听 PageView 左边界
/// 的 overscroll。
void main() {
  group('pulseSwipeShouldOpen', () {
    test('向右拖 96dp 以上打开', () {
      expect(pulseSwipeShouldOpen(dragDx: 97, velocity: 0), isTrue);
    });

    test('右甩够快（位移小）也打开', () {
      expect(pulseSwipeShouldOpen(dragDx: 12, velocity: 500), isTrue);
    });

    test('向左拖不打开', () {
      expect(pulseSwipeShouldOpen(dragDx: -120, velocity: -600), isFalse);
    });

    test('拖动太短太慢不打开', () {
      expect(pulseSwipeShouldOpen(dragDx: 40, velocity: 200), isFalse);
    });
  });

  testWidgets('第一页向右拖会请求打开负一屏', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseSwipeEntry(
            enabled: true,
            onOpen: () => opened++,
            child: PageView(
              children: const [
                Center(child: Text('overview')),
                Center(child: Text('config')),
                Center(child: Text('settings')),
              ],
            ),
          ),
        ),
      ),
    );

    // 手指从中间向右拖：第一页右边拖不出上一页，PageView 只能报告 overscroll。
    await tester.drag(find.byType(PageView), const Offset(160, 0));
    await tester.pumpAndSettle();

    expect(opened, 1);
  });

  testWidgets('不在第一页（enabled=false）时向右拖不触发', (tester) async {
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseSwipeEntry(
            enabled: false,
            onOpen: () => opened++,
            child: PageView(
              children: const [
                Center(child: Text('overview')),
                Center(child: Text('config')),
              ],
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.byType(PageView), const Offset(160, 0));
    await tester.pumpAndSettle();

    expect(opened, 0);
  });
}
