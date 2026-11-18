import 'package:clashdeck/core/update/semver.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SemVer', () {
    test('解析普通版本 / v 前缀 / build 元数据', () {
      expect(SemVer.tryParse('0.2.1')?.display, '0.2.1');
      expect(SemVer.tryParse('v0.2.1')?.display, '0.2.1');
      expect(SemVer.tryParse('1.2.3+2072')?.display, '1.2.3');
      expect(SemVer.tryParse(' 0.10.0 ')?.display, '0.10.0');
    });

    test('忽略 prerelease 后缀（只比较 major.minor.patch）', () {
      final beta = SemVer.tryParse('0.2.1-beta.2');
      final stable = SemVer.tryParse('0.2.1');
      expect(beta, isNotNull);
      expect(beta, stable);
      expect(beta!.compareTo(stable!), 0);
    });

    test('非法输入返回 null', () {
      expect(SemVer.tryParse(''), isNull);
      expect(SemVer.tryParse('0.2'), isNull);
      expect(SemVer.tryParse('abc'), isNull);
      expect(SemVer.tryParse('0.2.1.4'), isNull);
    });

    test('数值比较而不是字典序', () {
      expect(const SemVer(0, 10, 0) > const SemVer(0, 9, 9), isTrue);
      expect(const SemVer(1, 0, 0) > const SemVer(0, 99, 99), isTrue);
      expect(const SemVer(0, 10, 0) < const SemVer(1, 0, 0), isTrue);
    });
  });

  group('isNewerVersion', () {
    test('远端更新 / 相同 / 更旧', () {
      expect(isNewerVersion('v0.2.2', '0.2.1'), isTrue);
      expect(isNewerVersion('0.2.1', '0.2.1+2072'), isFalse);
      expect(isNewerVersion('0.2.0', '0.2.1'), isFalse);
    });

    test('任一版本无法解析时保守返回 false', () {
      expect(isNewerVersion('latest', '0.2.1'), isFalse);
      expect(isNewerVersion('0.2.2', ''), isFalse);
    });
  });

  group('shouldAutoCheck', () {
    final now = DateTime(2026, 11, 19, 12);

    test('从未检查过 → 允许', () {
      expect(shouldAutoCheck(null, now: now), isTrue);
    });

    test('24h 内 → 不允许；刚好 24h → 允许', () {
      expect(
        shouldAutoCheck(now.subtract(const Duration(hours: 23)), now: now),
        isFalse,
      );
      expect(
        shouldAutoCheck(now.subtract(const Duration(hours: 24)), now: now),
        isTrue,
      );
    });

    test('自定义间隔', () {
      expect(
        shouldAutoCheck(
          now.subtract(const Duration(hours: 2)),
          now: now,
          interval: const Duration(hours: 1),
        ),
        isTrue,
      );
    });
  });
}
