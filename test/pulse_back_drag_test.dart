import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/pulse_entry.dart';

void main() {
  test('未在滑出状态时不消费位移', () {
    expect(pulseBackDrag(dx: 40, delta: -12, active: false), 40);
  });

  test('正向位移继续累加', () {
    expect(pulseBackDrag(dx: 40, delta: 8, active: true), 40);
  });

  test('负向位移回收进度，最低回到 0', () {
    expect(pulseBackDrag(dx: 40, delta: -15, active: true), 25);
    expect(pulseBackDrag(dx: 10, delta: -35, active: true), 0);
    expect(pulseBackDrag(dx: 0, delta: -5, active: true), 0);
  });

  test('越过阈值后继续向右拖，进度必须继续增长', () {
    // 第一次越过 12px 阈值。
    var dx = pulseForwardDrag(dx: 10, delta: 20);
    final panelWidth = pulseDrawerPanelWidth(400);
    final first = pulseDrawerProgress(dragDx: dx, panelWidth: panelWidth);
    // active 之后的第二次正向 overscroll，仍在同一次拖拽里。
    dx = pulseForwardDrag(dx: dx, delta: 60);
    final second = pulseDrawerProgress(dragDx: dx, panelWidth: panelWidth);
    expect(second, greaterThan(first));
    expect(second, (10 + 20 + 60) / panelWidth);
  });

  test('正向累计不会被负向 delta 拉低', () {
    expect(pulseForwardDrag(dx: 40, delta: -10), 40);
    expect(pulseForwardDrag(dx: 40, delta: 0), 40);
  });
}
