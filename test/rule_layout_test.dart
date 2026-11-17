import 'package:clashdeck/core/edit/rule_layout.dart';
import 'package:clashdeck/core/model/rule_zone.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ruleZoneOf', () {
    test('精确规则落在本地区', () {
      for (final rule in <String>[
        'DOMAIN,example.com,DIRECT',
        'DOMAIN-SUFFIX,example.com,PROXY',
        'DOMAIN-KEYWORD,github,PROXY',
        'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
        'PROCESS-NAME,Telegram.exe,PROXY',
        'DST-PORT,443,PROXY',
      ]) {
        expect(ruleZoneOf(rule), RuleZone.local, reason: rule);
      }
    });

    test('规则集落在线区、GEOSITE/GEOIP 落 GEO 区', () {
      for (final rule in <String>[
        'RULE-SET,loyal-reject,REJECT',
        'rule-set,loyal-proxy,PROXY',
      ]) {
        expect(ruleZoneOf(rule), RuleZone.online, reason: rule);
      }
      for (final rule in <String>['GEOSITE,openai,PROXY', 'GEOIP,CN,DIRECT']) {
        expect(ruleZoneOf(rule), RuleZone.geo, reason: rule);
      }
    });

    test('兜底规则单独成区', () {
      expect(ruleZoneOf('MATCH,PROXY'), RuleZone.terminal);
      expect(ruleZoneOf('FINAL,DIRECT'), RuleZone.terminal);
      expect(isTerminalRule('MATCH,兜底'), isTrue);
      expect(isTerminalRule('DOMAIN,a.com,DIRECT'), isFalse);
    });

    test('类型解析容忍行内注释与空格', () {
      expect(ruleTypeOf('  rule-set , loyal-x,PROXY # 注释'), 'RULE-SET');
      expect(ruleZoneOf('DOMAIN,a.com#x,DIRECT'), RuleZone.local);
    });
  });

  group('RuleLayout.normalize', () {
    const messy = '''
mixed-port: 7890
proxies: []
rules:
  # 大规则集
  - GEOSITE,openai,PROXY
  - RULE-SET,loyal-reject,REJECT
  - MATCH,PROXY
  # 手写精确规则
  - DOMAIN-SUFFIX,example.com,DIRECT # 我的站点
  - IP-CIDR,10.0.0.0/8,DIRECT
''';

    test('本地块在前、在线块与 GEO 居中、MATCH 最后', () {
      final out = RuleLayout.normalize(messy);
      final types = <String>[
        for (final line in out.split('\n'))
          if (line.trim().startsWith('- '))
            line.trim().substring(2).split(',').first,
      ];
      expect(types, [
        'DOMAIN-SUFFIX',
        'IP-CIDR',
        'RULE-SET',
        'GEOSITE',
        'MATCH',
      ]);
    });

    test('注释跟着自己那条规则走，行内注释保留', () {
      final out = RuleLayout.normalize(messy);
      final lines = out.split('\n').map((line) => line.trim()).toList();
      final commentAt = lines.indexOf('# 大规则集');
      expect(commentAt, greaterThan(-1));
      expect(lines[commentAt + 1], startsWith('- GEOSITE,openai,PROXY'));
      expect(
        lines[lines.indexOf('# 手写精确规则') + 1],
        '- DOMAIN-SUFFIX,example.com,DIRECT # 我的站点',
      );
    });

    test('段外内容逐字不变', () {
      final out = RuleLayout.normalize(messy);
      expect(out.split('rules:').first, messy.split('rules:').first);
    });

    test('幂等：已经排好就不返回新文本', () {
      final once = RuleLayout.normalize(messy);
      final twice = RuleLayout.normalize(once);
      expect(twice, once);
      expect(identical(twice, once), isTrue);
    });

    test('没有 rules 段时原样返回', () {
      const text = 'mixed-port: 7890\nproxies: []\n';
      expect(RuleLayout.normalize(text), text);
    });
  });

  group('RuleLayout.insertRule', () {
    const ordered = '''
proxies: []
rules:
  - DOMAIN-SUFFIX,example.com,DIRECT
  - RULE-SET,loyal-reject,REJECT
  - MATCH,PROXY
''';

    test('本地新规则插到本地块首位', () {
      final out = RuleLayout.insertRule(ordered, 'DOMAIN-KEYWORD,github,PROXY');
      final rules = out.split('rules:').last;
      final firstRule = rules
          .split('\n')
          .firstWhere((line) => line.trim().startsWith('- '))
          .trim();
      expect(firstRule, '- DOMAIN-KEYWORD,github,PROXY');
    });

    test('手写 GEOSITE 进 GEO 区，排在规则集之后、MATCH 之前', () {
      final out = RuleLayout.insertRule(ordered, 'GEOSITE,openai,PROXY');
      final types = <String>[
        for (final line in out.split('\n'))
          if (line.trim().startsWith('- '))
            line.trim().substring(2).split(',').first,
      ];
      expect(types, ['DOMAIN-SUFFIX', 'RULE-SET', 'GEOSITE', 'MATCH']);
    });

    test('MATCH 追加到末尾', () {
      final out = RuleLayout.insertRule(ordered, 'FINAL,DIRECT');
      final last = out
          .split('\n')
          .lastWhere((line) => line.trim().startsWith('- '))
          .trim();
      expect(last, '- FINAL,DIRECT');
    });

    test('rules: [] 会被展开成块', () {
      const flow = 'rules: []\nproxies: []\n';
      final out = RuleLayout.insertRule(flow, 'DOMAIN,a.com,DIRECT');
      expect(out.contains('rules:\n  - DOMAIN,a.com,DIRECT'), isTrue);
    });

    test('没有 rules 段时新建该段', () {
      const text = 'mixed-port: 7890\n';
      final out = RuleLayout.insertRule(text, 'DOMAIN,a.com,DIRECT');
      expect(out.contains('rules:\n  - DOMAIN,a.com,DIRECT'), isTrue);
    });
  });

  group('文档级封装', () {
    test('normalizeDoc 结果可解析，且已排好时返回同一实例', () {
      const messy =
          'proxies: []\nrules:\n  - RULE-SET,loyal-x,PROXY\n  - DOMAIN,a.com,DIRECT\n  - MATCH,PROXY\n';
      final doc = YamlDoc.parse(messy);
      final fixed = RuleLayout.normalizeDoc(doc);
      expect(fixed.isValid, isTrue);
      expect(
        fixed.text.indexOf('DOMAIN,a.com,DIRECT'),
        lessThan(fixed.text.indexOf('RULE-SET,loyal-x,PROXY')),
      );
      expect(identical(RuleLayout.normalizeDoc(fixed), fixed), isTrue);
    });

    test('insertRuleDoc 插对位置且文档仍可解析', () {
      const text =
          'proxies: []\nrules:\n  - DOMAIN,a.com,DIRECT\n  - MATCH,PROXY\n';
      final doc = RuleLayout.insertRuleDoc(
        YamlDoc.parse(text),
        'GEOSITE,openai,PROXY',
      );
      expect(doc.isValid, isTrue);
      expect(
        doc.text.indexOf('GEOSITE,openai,PROXY'),
        lessThan(doc.text.indexOf('MATCH,PROXY')),
      );
    });
  });

  group('hasTerminalNotLast', () {
    test('MATCH 在中间时报警', () {
      const text = 'rules:\n  - MATCH,PROXY\n  - DOMAIN,a.com,DIRECT\n';
      expect(RuleLayout.hasTerminalNotLast(text), isTrue);
    });

    test('MATCH 在末尾时安静', () {
      const text = 'rules:\n  - DOMAIN,a.com,DIRECT\n  - MATCH,PROXY\n';
      expect(RuleLayout.hasTerminalNotLast(text), isFalse);
    });
  });
}
