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
}
