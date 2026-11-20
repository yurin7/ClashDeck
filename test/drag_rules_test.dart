import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/widgets/drag_rules.dart';

void main() {
  group('组卡拖放规则', () {
    test('拖回源组直接拒绝，且提示「已在组里」', () {
      expect(
        shouldAcceptNodeDrop(
          fromGroup: 'DEFAULT',
          targetGroup: 'DEFAULT',
          relay: false,
          alreadyMember: true,
        ),
        isFalse,
      );
      expect(
        shouldHintDuplicate(
          fromGroup: 'DEFAULT',
          targetGroup: 'DEFAULT',
          alreadyMember: true,
        ),
        isTrue,
      );
    });

    test('已在目标组的节点不重复加入', () {
      expect(
        shouldAcceptNodeDrop(
          fromGroup: 'A',
          targetGroup: 'B',
          relay: false,
          alreadyMember: true,
        ),
        isFalse,
      );
    });

    test('链式组整卡一律拒绝（只有链内间隙能接）', () {
      expect(
        shouldAcceptNodeDrop(
          fromGroup: 'A',
          targetGroup: '链式',
          relay: true,
          alreadyMember: false,
        ),
        isFalse,
      );
    });

    test('跨组的新节点可以放入普通组', () {
      expect(
        shouldAcceptNodeDrop(
          fromGroup: 'A',
          targetGroup: 'B',
          relay: false,
          alreadyMember: false,
        ),
        isTrue,
      );
    });
  });
}
