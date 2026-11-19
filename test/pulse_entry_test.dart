import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/ui/pulse_entry.dart';

/// Pulse 是「左侧 80% 遮罩层」：概览页左缘 28dp 手势带内向右拖才拉出，
/// 面板从左边滑入；屏幕中部仍交给 PageView 翻页，两者不再抢手势。
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
    test('按住右滑时进度跟随位移', () {
      expect(pulseDrawerProgress(dragDx: 160, panelWidth: 320), 0.5);
    });

    test('反向拖动与超范围都夹在 0..1', () {
      expect(pulseDrawerProgress(dragDx: -80, panelWidth: 320), 0);
      expect(pulseDrawerProgress(dragDx: 640, panelWidth: 320), 1);
    });

    test('屏宽异常时返回 0，避免除零', () {
      expect(pulseDrawerProgress(dragDx: 100, panelWidth: 0), 0);
    });
  });
  group('overscroll 起手阈值', () {
    test('累计 12dp 才开始拉抽屉', () {
      expect(kPulseOverscrollStartDx, 12);
      expect(kPulseOverscrollStartDx, greaterThan(0));
    });

    test('概览页右滑 200dp 打开、只滑 100dp 回弹', () {
      const width = 400.0;
      final panel = pulseDrawerPanelWidth(width);
      final open = pulseDrawerProgress(dragDx: 200, panelWidth: panel);
      final half = pulseDrawerProgress(dragDx: 100, panelWidth: panel);
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

    test('松手不过半且没有右甩速度就回弹', () {
      expect(pulseDrawerShouldOpen(progress: 0.34, velocity: 0), isFalse);
    });

    test('速度够快（右甩）即使位移不足也打开', () {
      expect(pulseDrawerShouldOpen(progress: 0.1, velocity: 301), isTrue);
    });

    test('阈值是严格大于：0.35 与 300 都不打开', () {
      expect(pulseDrawerShouldOpen(progress: 0.35, velocity: 0), isFalse);
      expect(pulseDrawerShouldOpen(progress: 0.2, velocity: 300), isFalse);
      expect(pulseDrawerShouldOpen(progress: 0.351, velocity: 0), isTrue);
    });
  });

  group('pulseDrawerShouldClose', () {
    test('拖回四成以上就收起', () {
      expect(pulseDrawerShouldClose(progress: 0.64, velocity: 0), isTrue);
    });

    test('只拖了一点点且没有左甩就回弹', () {
      expect(pulseDrawerShouldClose(progress: 0.66, velocity: 0), isFalse);
    });

    test('左甩够快就收起', () {
      expect(pulseDrawerShouldClose(progress: 0.9, velocity: -301), isTrue);
    });
  });
  group('pulseShouldBlockPager', () {
    test('抽屉打开时禁止翻页', () {
      expect(pulseShouldBlockPager(open: true, reveal: 0), isTrue);
    });

    test('抽屉滑出一半时也禁止翻页', () {
      expect(pulseShouldBlockPager(open: false, reveal: 0.4), isTrue);
    });

    test('完全收起后恢复翻页', () {
      expect(pulseShouldBlockPager(open: false, reveal: 0), isFalse);
    });
  });

  group('pulsePagerPhysics', () {
    test('打开时不可滚', () {
      expect(
        pulsePagerPhysics(open: true),
        isA<NeverScrollableScrollPhysics>(),
      );
    });

    test('关闭时是正常翻页', () {
      expect(pulsePagerPhysics(open: false), isA<PageScrollPhysics>());
    });
  });
  group('pulsePagerLocked', () {
    test('打开且不在拖拽时禁滑', () {
      expect(pulsePagerLocked(open: true, dragging: false), isTrue);
    });

    test('拖拽过程中不禁滑，避免打断手势', () {
      expect(pulsePagerLocked(open: true, dragging: true), isFalse);
    });

    test('抽屉关闭时不禁滑', () {
      expect(pulsePagerLocked(open: false, dragging: false), isFalse);
    });
  });
}
