import 'package:clashdeck/core/edit/rule_presets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('sanitizeGroupName', () {
    test('去掉括号说明', () {
      expect(sanitizeGroupName('OpenAI（含 ChatGPT）'), 'OpenAI');
      expect(sanitizeGroupName('微软 Microsoft'), '微软 Microsoft');
      expect(sanitizeGroupName('苹果 Apple 域名'), '苹果 Apple 域名');
    });

    test('斜杠换成空格并压缩空白', () {
      expect(sanitizeGroupName('内网 / 本机地址'), '内网 本机地址');
      expect(sanitizeGroupName('流媒体/视频'), '流媒体 视频');
      expect(sanitizeGroupName('  广告与跟踪  '), '广告与跟踪');
    });

    test('全空回退到 PROXY', () {
      expect(sanitizeGroupName('   '), 'PROXY');
      expect(sanitizeGroupName('（只有说明）'), 'PROXY');
    });

    test('超长截断到 24 个字符且去尾空格', () {
      final long = sanitizeGroupName('一二三四五六七八九十' * 3);
      expect(long.length, 24);
      expect(long.endsWith(' '), isFalse);

      final trailing = sanitizeGroupName('${'a' * 23} b');
      expect(trailing.length, 23);
      expect(trailing, 'a' * 23);
    });
  });
}
