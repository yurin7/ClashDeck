import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/edit/import_rules.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = '''
mixed-port: 7890
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: 11111111-1111-1111-1111-111111111111
  - name: n2
    type: ss
    server: b.example.com
    port: 443
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - n1
      - DIRECT
rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
''';

YamlDoc _doc([String text = _base]) => YamlDoc.parse(text);

void main() {
  group('importRules：纯规则行', () {
    test('插入到 MATCH 之前，且能识别 no-resolve', () {
      final out = importRules(_doc(), '''
# 我自己的规则
DOMAIN-SUFFIX,google.com,PROXY
IP-CIDR,10.0.0.0/8,DIRECT,no-resolve
''');
      expect(out.rulesAdded, 2);
      expect(out.warnings, isEmpty);
      final rules = Profile.from(out.doc).rules.map((r) => r.raw).toList();
      // 本地精确规则统一排在在线（GEOIP/RULE-SET/GEOSITE）之前。
      expect(rules, [
        'DOMAIN-SUFFIX,google.com,PROXY',
        'IP-CIDR,10.0.0.0/8,DIRECT,no-resolve',
        'GEOIP,CN,DIRECT',
        'MATCH,PROXY',
      ]);
      expect(out.summary, contains('新增 2 条规则'));
    });

    test('允许 YAML 列表前缀与重复规则去重', () {
      final out = importRules(_doc(), '''
- DOMAIN-SUFFIX,google.com,PROXY
- domain-suffix, google.com , proxy
- GEOIP,CN,DIRECT
''');
      expect(out.rulesAdded, 1);
      expect(out.rulesSkipped, 2, reason: '大小写/空格不同的同一条规则 + 已有规则');
    });

    test('未知类型与不完整规则进 warnings，只导入认得的那条', () {
      final doc = _doc();
      final out = importRules(
        doc,
        'BOGUS,x,y\nDOMAIN-SUFFIX,only-two\nDOMAIN,ok.example.com,PROXY',
      );
      expect(out.rulesAdded, 1);
      expect(out.warnings.length, 2);
      expect(out.warnings.first, contains('不是已知规则类型'));
      expect(out.warnings.last, contains('规则不完整'));
      expect(out.doc.text, isNot(doc.text));
    });

    test('空输入抛异常', () {
      expect(
        () => importRules(_doc(), '   \n  '),
        throwsA(
          isA<ConfigEditException>().having(
            (e) => e.message,
            'message',
            contains('没有可导入的内容'),
          ),
        ),
      );
    });

    test('完全认不出来时抛出带首条提示的异常', () {
      expect(
        () => importRules(_doc(), 'hello world\n你好'),
        throwsA(
          isA<ConfigEditException>().having(
            (e) => e.message,
            'message',
            contains('不是已知规则类型'),
          ),
        ),
      );
    });
  });

  group('importRules：带策略组的配置片段', () {
    const fragment = '''
proxy-groups:
  - name: 媒体
    type: select
    proxies:
      - n1
      - n2
      - 不存在节点
  - name: PROXY
    type: select
    proxies:
      - n2
rules:
  - DOMAIN-SUFFIX,netflix.com,媒体
  - DOMAIN-SUFFIX,github.com,PROXY
''';

    test('新建策略组、过滤不存在成员、补全已存在组、规则指向新组', () {
      final out = importRules(_doc(), fragment);
      expect(out.groupsAdded, ['媒体']);
      expect(out.groupsMerged, ['PROXY']);
      expect(out.warnings.any((w) => w.contains('不存在节点')), isTrue);

      final profile = Profile.from(out.doc);
      expect(profile.group('媒体')?.members, ['n1', 'n2']);
      expect(profile.group('PROXY')?.members, ['n1', 'DIRECT', 'n2']);
      // 两条 DOMAIN-SUFFIX 属本地精确规则，排在 GEOIP（在线区）之前。
      expect(profile.rules.map((r) => r.target), [
        '媒体',
        'PROXY',
        'DIRECT',
        'PROXY',
      ]);
      expect(out.rulesAdded, 2);
    });

    test('规则目标缺失时自动建 select 组（成员只有 DIRECT），可关闭', () {
      final out = importRules(_doc(), 'DOMAIN,example.com,新组');
      expect(out.targetGroupsCreated, ['新组']);
      final group = Profile.from(out.doc).group('新组');
      expect(group?.type, 'select');
      expect(group?.members, ['DIRECT']);

      final noCreate = importRules(
        _doc(),
        'DOMAIN,example.com,另一个组',
        createMissingGroups: false,
      );
      expect(noCreate.targetGroupsCreated, isEmpty);
      expect(Profile.from(noCreate.doc).group('另一个组'), isNull);
    });

    test('合并 rule-providers / proxy-providers', () {
      final out = importRules(_doc(), '''
rule-providers:
  cn:
    type: http
    behavior: domain
    url: https://example.com/cn.yaml
proxy-providers:
  airport:
    type: http
    url: https://example.com/sub.yaml
rules:
  - RULE-SET,cn,DIRECT
''');
      expect(out.providersAdded, [
        'rule-providers/cn',
        'proxy-providers/airport',
      ]);
      final root = out.doc.plainRoot;
      expect((root['rule-providers'] as Map)['cn'], isA<Map>());
      expect((root['proxy-providers'] as Map)['airport'], isA<Map>());
      expect(out.rulesAdded, 1);
      // 已有同名 provider 时不覆盖。
      final again = importRules(
        out.doc,
        'rule-providers:\n  cn:\n    type: http\n    url: https://x/y.yaml',
      );
      expect(again.providersAdded, isEmpty);
      expect(again.warnings.first, contains('未覆盖'));
    });

    test('YAML 片段解析失败时回退到逐行解析并留提示', () {
      final out = importRules(_doc(), '''
proxy-groups:
  - name: 组
   bad indent
rules:
  - DOMAIN,x.example.com,PROXY
''');
      expect(out.rulesAdded, 1);
      expect(out.warnings.any((w) => w.contains('按 YAML 解析失败')), isTrue);
    });
  });
  group('parseRuleProviderBody：behavior 推断', () {
    test('ACL4SSR 的 classical 列表不会被当成 domain', () {
      final body = parseRuleProviderBody('''
# 内容：Microsoft
# 数量：3条
DOMAIN-KEYWORD,1drv
DOMAIN-SUFFIX,microsoft.com
DOMAIN-SUFFIX,office.com
''', url: 'https://example.com/Microsoft.list');
      expect(body, isNotNull);
      expect(body!.behavior, 'classical');
      expect(body.entries.first, 'DOMAIN-KEYWORD,1drv');
    });

    test('Loyalsoldier 的纯域名列表仍然是 domain', () {
      final body = parseRuleProviderBody('''
payload:
  - '+.openai.com'
  - '+.chatgpt.com'
''');
      expect(body!.behavior, 'domain');
    });

    test('纯 IP 段列表是 ipcidr', () {
      final body = parseRuleProviderBody('''
payload:
  - 10.0.0.0/8
  - 192.168.0.0/16
''');
      expect(body!.behavior, 'ipcidr');
    });
  });

  group('importRuleProvider：写进配置', () {
    test('classical provider 的 behavior 原样写进 rule-providers', () {
      final body = parseRuleProviderBody(
        'DOMAIN-SUFFIX,apple.com\nDOMAIN-SUFFIX,icloud.com\n',
        url: 'https://example.com/Apple.list',
      )!;
      final out = importRuleProvider(
        _doc(),
        body: body,
        name: 'acl-apple',
        target: '媒体',
        url: 'https://example.com/Apple.list',
      );
      final providers =
          (out.doc.plainRoot['rule-providers'] as Map)['acl-apple'] as Map;
      expect(providers['behavior'], 'classical');
      expect(providers['url'], 'https://example.com/Apple.list');
      expect(
        Profile.from(out.doc).rules.map((r) => r.raw),
        contains('RULE-SET,acl-apple,媒体'),
      );
    });
  });

  group('importRuleProvider：同名 provider 的 behavior 纠正', () {
    test('旧定义是 domain、这次是 classical 时覆盖并留提示', () {
      final first = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(
          'DOMAIN-SUFFIX,apple.com\n',
          url: 'https://example.com/Apple.list',
        )!,
        name: 'acl-apple',
        target: '媒体',
        url: 'https://example.com/Apple.list',
      );
      // 模拟老版本写坏的 provider。
      final broken = ConfigOps.setAtOrCreate(first.doc, const [
        'rule-providers',
        'acl-apple',
        'behavior',
      ], 'domain');

      final out = importRuleProvider(
        broken,
        body: parseRuleProviderBody(
          'DOMAIN-SUFFIX,apple.com\nDOMAIN-KEYWORD,icloud\n',
          url: 'https://example.com/Apple.list',
        )!,
        name: 'acl-apple',
        target: '媒体',
        url: 'https://example.com/Apple.list',
      );

      final providers =
          (out.doc.plainRoot['rule-providers'] as Map)['acl-apple'] as Map;
      expect(providers['behavior'], 'classical');
      expect(out.providersUpdated, ['rule-providers/acl-apple']);
      expect(out.providersAdded, isEmpty);
      expect(
        out.warnings.any(
          (w) => w.contains('domain') && w.contains('classical'),
        ),
        isTrue,
      );
      expect(out.summary, contains('更新 1 个同名规则集'));
    });

    test('behavior 一致时沿用旧定义、只留一条提示', () {
      final first = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody('DOMAIN-SUFFIX,apple.com\n')!,
        name: 'acl-apple',
        target: '媒体',
        url: 'https://example.com/Apple.list',
      );
      final out = importRuleProvider(
        first.doc,
        body: parseRuleProviderBody('DOMAIN-SUFFIX,icloud.com\n')!,
        name: 'acl-apple',
        target: '媒体',
        url: 'https://example.com/Apple.list',
      );
      expect(out.providersUpdated, isEmpty);
      expect(out.providersAdded, isEmpty);
      expect(out.warnings.single, contains('沿用原有定义'));
    });
  });

  group('insertRuleLines：批量插 GEOSITE', () {
    test('插在 MATCH 之前、重复的跳过', () {
      final out = insertRuleLines(_doc(), [
        'GEOSITE,openai,PROXY',
        'GEOSITE,netflix,媒体',
        'GEOSITE,openai,PROXY',
      ]);
      expect(out.rulesAdded, 2);
      expect(out.rulesSkipped, 1);
      final rules = Profile.from(out.doc).rules.map((r) => r.raw).toList();
      expect(
        rules.indexOf('GEOSITE,openai,PROXY'),
        lessThan(rules.indexWhere((r) => r.startsWith('MATCH'))),
      );
      expect(rules.last, startsWith('MATCH'));
    });

    test('目标组不存在时自动建组', () {
      final out = insertRuleLines(_doc(), ['GEOSITE,openai,新目标']);
      expect(out.targetGroupsCreated, ['新目标']);
      expect(Profile.from(out.doc).group('新目标')?.members, ['DIRECT']);
    });
  });
}
