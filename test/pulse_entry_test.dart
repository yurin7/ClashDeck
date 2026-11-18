import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/pulse_entry.dart';

/// 0.3.2 起 Pulse 改右侧 80% 抽屉：手势阈值、面板宽度与分页物理都收在这里，
/// 方便单测。0.3.0 的 bug 是入口手势被 PageView 的手势竞技场吃掉，
/// 现在第 0 页直接禁用横向滚动（[pulsePagerPhysics]）。
void main() {
  group('pulseDrawerPanelWidth', () {
    test('面板宽 = 屏宽 * 0.8', () {
      expect(pulseDrawerPanelWidth(400), 320);
      expect(pulseDrawerPanelWidth(1000), 800);
    });

    test('窄屏也不会超过屏宽', () {
      expect(pulseDrawerPanelWidth(10), lessThanOrEqualTo(10));
    });
  });

  group('pulseDrawerProgress', () {
    test('按住左滑时进度跟随位移', () {
      expect(pulseDrawerProgress(dragDx: -160, panelWidth: 320), 0.5);
    });

    test('反向拖动与超范围都夹在 0..1', () {
      expect(pulseDrawerProgress(dragDx: 80, panelWidth: 320), 0);
      expect(pulseDrawerProgress(dragDx: -640, panelWidth: 320), 1);
    });

    test('屏宽异常时返回 0，避免除零', () {
      expect(pulseDrawerProgress(dragDx: -100, panelWidth: 0), 0);
    });
  });

  group('pulseDrawerShouldOpen', () {
    test('松手过半就打开', () {
      expect(pulseDrawerShouldOpen(progress: 0.36, velocity: 0), isTrue);
    });

    test('松手不过半且没有左甩速度就回弹', () {
      expect(pulseDrawerShouldOpen(progress: 0.34, velocity: 0), isFalse);
    });

    test('速度够快（左甩）即使位移不足也打开', () {
      expect(pulseDrawerShouldOpen(progress: 0.1, velocity: -301), isTrue);
    });

    test('阈值是严格大于：0.35 与 -300 都不打开', () {
      expect(pulseDrawerShouldOpen(progress: 0.35, velocity: 0), isFalse);
      expect(pulseDrawerShouldOpen(progress: 0.2, velocity: -300), isFalse);
      expect(pulseDrawerShouldOpen(progress: 0.351, velocity: 0), isTrue);
    });
  });

  group('pulseDrawerShouldClose', () {
    test('拖回四成以上就收起', () {
      expect(pulseDrawerShouldClose(progress: 0.64, velocity: 0), isTrue);
    });

    test('只拖了一点点且没有右甩就回弹', () {
      expect(pulseDrawerShouldClose(progress: 0.66, velocity: 0), isFalse);
    });

    test('右甩够快就收起', () {
      expect(pulseDrawerShouldClose(progress: 0.9, velocity: 301), isTrue);
    });
  });

  group('pulsePagerPhysics', () {
    test('第 0 页禁用横向滚动', () {
      expect(pulsePagerPhysics(0), isA<NeverScrollableScrollPhysics>());
    });

    test('其它页保留分页滚动', () {
      expect(pulsePagerPhysics(1), isA<PageScrollPhysics>());
      expect(pulsePagerPhysics(2), isA<PageScrollPhysics>());
    });
  });
}
