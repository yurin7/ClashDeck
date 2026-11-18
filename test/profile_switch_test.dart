import 'package:clashdeck/core/edit/profile_switch.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('profileRowPhase', () {
    test('普通行：既没在跑也没在切', () {
      expect(
        profileRowPhase(
          'a.yaml',
          activeFileName: 'b.yaml',
          switchingFileName: null,
        ),
        ProfileRowPhase.normal,
      );
      expect(
        profileRowPhase(
          'a.yaml',
          activeFileName: null,
          switchingFileName: null,
        ),
        ProfileRowPhase.normal,
      );
    });

    test('运行中的行标 active', () {
      expect(
        profileRowPhase(
          'a.yaml',
          activeFileName: 'a.yaml',
          switchingFileName: null,
        ),
        ProfileRowPhase.active,
      );
    });

    test('切换中的行优先于运行中（旧内核已停，不能再显示「运行中」）', () {
      expect(
        profileRowPhase(
          'a.yaml',
          activeFileName: 'a.yaml',
          switchingFileName: 'a.yaml',
        ),
        ProfileRowPhase.switching,
      );
      // 切换别的配置时，原来运行的那一行仍是 active。
      expect(
        profileRowPhase(
          'a.yaml',
          activeFileName: 'a.yaml',
          switchingFileName: 'b.yaml',
        ),
        ProfileRowPhase.active,
      );
    });
  });
}
