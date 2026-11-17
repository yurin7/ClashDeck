import 'package:clashdeck/core/edit/import_plan.dart';
import 'package:clashdeck/core/model/rule_zone.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ruleZoneOf', () {
    test('RULE-SET 归在线区', () {
      expect(ruleZoneOf('RULE-SET,loyal-proxy,PROXY'), RuleZone.online);
    });

    test('GEOSITE / GEOIP 归 GEO 区', () {
      expect(ruleZoneOf('GEOSITE,netflix,媒体'), RuleZone.geo);
      expect(ruleZoneOf('GEOIP,CN,DIRECT'), RuleZone.geo);
    });

    test('MATCH / FINAL 归兜底区', () {
      expect(ruleZoneOf('MATCH,PROXY'), RuleZone.terminal);
      expect(ruleZoneOf('FINAL,DIRECT'), RuleZone.terminal);
    });

    test('其它规则归本地区', () {
      expect(ruleZoneOf('DOMAIN-SUFFIX,google.com,PROXY'), RuleZone.local);
      expect(ruleZoneOf('PROCESS-NAME,Telegram,PROXY'), RuleZone.local);
    });
  });

  group('normalizeRuleSetUrl', () {
    test('去掉 @分支、query、末尾斜杠后三种写法一致', () {
      const base = 'https://raw.githubusercontent.com/a/b/main/direct.txt';
      expect(normalizeRuleSetUrl('$base?x=1'), base);
      expect(normalizeRuleSetUrl('$base/'), base);
      expect(normalizeRuleSetUrl('$base@master'), base);
    });

    test('保留 https 的双斜杠', () {
      expect(
        normalizeRuleSetUrl('https://a.example.com/b.txt'),
        'https://a.example.com/b.txt',
      );
    });

    test('空串安全', () {
      expect(normalizeRuleSetUrl('   '), '');
    });
  });

  group('looksLikeSameName', () {
    test('大小写与标点差异算同名', () {
      expect(looksLikeSameName('Loyal-Reject', 'loyal reject'), isTrue);
      expect(looksLikeSameName('Netflix', 'netfilx'), isTrue);
    });

    test('明显不同的名字不算同名', () {
      expect(looksLikeSameName('Netflix', 'Spotify'), isFalse);
      expect(looksLikeSameName('acl-cn', 'loyal-gfw'), isFalse);
    });

    test('空名字一律不算同名', () {
      expect(looksLikeSameName('', 'netflix'), isFalse);
    });
  });
}
