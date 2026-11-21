import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/widgets/drag_state.dart';

void main() {
  late DragState state;

  setUp(() => state = DragState());

  test('开始拖拽记录源位置，结束后可取回弹请求', () {
    state.begin(
      member: '日本 01',
      group: 'DEFAULT',
      sourceRect: const Rect.fromLTWH(12, 30, 100, 36),
      feedbackSize: const Size(100, 36),
    );
    expect(state.dragging, isTrue);
    expect(state.blocked, isFalse);

    expect(state.end(const Offset(200, 300)), isTrue);
    expect(state.dragging, isFalse);

    final snap = state.takeSnapBack();
    expect(snap, isNotNull);
    expect(snap!.member, '日本 01');
    expect(snap.fromGroup, 'DEFAULT');
    expect(snap.sourceRect, const Rect.fromLTWH(12, 30, 100, 36));
    expect(snap.endOffset, const Offset(200, 300));
    expect(snap.feedbackSize, const Size(100, 36));
    expect(state.animating, isTrue);
    // 播放期间不重复取，避免叠两个浮层。
    expect(state.takeSnapBack(), isNull);

    state.finishSnapBack();
    expect(state.animating, isFalse);
    expect(state.sourceRect, isNull);
    expect(state.takeSnapBack(), isNull);
  });

  test('落在合法目标上不回弹', () {
    state.begin(
      member: 'a',
      group: 'g1',
      sourceRect: const Rect.fromLTWH(0, 0, 80, 32),
      feedbackSize: const Size(80, 32),
    );
    state.markAccepted();
    expect(state.end(const Offset(10, 10)), isFalse);
    expect(state.takeSnapBack(), isNull);
  });

  test('重复悬停标记 blocked，回弹请求带上重复组名', () {
    state.begin(
      member: 'a',
      group: 'g1',
      sourceRect: const Rect.fromLTWH(0, 0, 80, 32),
      feedbackSize: const Size(80, 32),
    );
    state.hintDuplicate('g2');
    expect(state.blocked, isTrue);
    expect(state.duplicateGroup, 'g2');

    state.end(const Offset(5, 5));
    final snap = state.takeSnapBack();
    expect(snap!.duplicateGroup, 'g2');

    state.finishSnapBack();
    expect(state.duplicateGroup, isNull);
    expect(state.blocked, isFalse);
  });

  test('未开始拖拽时 end 返回 false', () {
    expect(state.end(const Offset(1, 1)), isFalse);
    expect(state.takeSnapBack(), isNull);
  });
}
