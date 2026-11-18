import 'package:clashdeck/ui/overview_page.dart';
import 'package:flutter_test/flutter_test.dart';

/// 概览左滑进 Pulse 的阈值：整页横向左扫够远或够快。
///
/// 右边缘起手会和 Android 手势导航的「返回」抢系统手势（实测会直接回桌面），
/// 所以入口不吃边缘，只要横向位移/速度达到阈值即可；横向胶囊行自己会赢得
/// 手势竞技场，不会被误触发。
void main() {
  test('左扫 100dp 打开', () {
    expect(pulseDragShouldOpen(dx: -101, velocity: 0), isTrue);
  });

  test('快速左扫（位移小）也打开', () {
    expect(pulseDragShouldOpen(dx: -10, velocity: -500), isTrue);
  });

  test('左扫太慢太短不打开', () {
    expect(pulseDragShouldOpen(dx: -10, velocity: -200), isFalse);
  });

  test('右扫不打开', () {
    expect(pulseDragShouldOpen(dx: 120, velocity: 600), isFalse);
  });

  test('几乎没动不打开', () {
    expect(pulseDragShouldOpen(dx: 0, velocity: 0), isFalse);
  });
}
