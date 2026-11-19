import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/pulse_entry.dart';

/// 0.3.2 起 Pulse 是右侧 80% 抽屉；0.3.3 起只有「概览页右缘 28dp 手势带」
/// 往左滑才拉抽屉，屏幕中部仍交给 PageView 翻页，两者不再抢手势。
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

  group('右缘手势带', () {
    test('起手点在右缘 28dp 内才接管', () {
      expect(pulseEdgeDragStarts(startX: 972, screenWidth: 1000), isTrue);
      expect(pulseEdgeDragStarts(startX: 973, screenWidth: 1000), isTrue);
      expect(pulseEdgeDragStarts(startX: 971, screenWidth: 1000), isFalse);
      expect(pulseEdgeDragStarts(startX: 500, screenWidth: 1000), isFalse);
    });

    test('屏宽异常时不接管', () {
      expect(pulseEdgeDragStarts(startX: 0, screenWidth: 0), isFalse);
    });

    test('从右缘左拖 200dp 打开、只拖 100dp 回弹', () {
      const width = 400.0;
      final panel = pulseDrawerPanelWidth(width);
      final open = pulseDrawerProgress(dragDx: -200, panelWidth: panel);
      final half = pulseDrawerProgress(dragDx: -100, panelWidth: panel);
      expect(open, closeTo(0.625, 0.001));
      expect(half, closeTo(0.3125, 0.001));
      expect(pulseDrawerShouldOpen(progress: open, velocity: 0), isTrue);
      expect(pulseDrawerShouldOpen(progress: half, velocity: 0), isFalse);
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
}
