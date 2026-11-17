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
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - n1
      - DIRECT
  - name: 媒体
    type: select
    proxies:
      - n1
rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
''';

YamlDoc _doc([String text = _base]) => YamlDoc.parse(text);

/// 取自 Loyalsoldier/clash-rules 的真实结构（payload 列表，域名）。
const _domainPayload = '''
payload:
  - '+.2mdn.net'
  - 'adservice.google.com'
  - 'aod.itunes.apple.com'
''';

/// 同一项目的 IP 段文件。
const _cidrPayload = '''
payload:
  - '1.0.1.0/24'
  - '1.0.2.0/23'
  - '223.255.252.0/23'
''';

void main() {
  group('parseRuleProviderBody：识别 payload 文件', () {
    test('域名列表 → behavior=domain，并从 URL 取名', () {
      final body = parseRuleProviderBody(
        _domainPayload,
        url: 'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/direct.txt',
      );
      expect(body, isNotNull);
      expect(body!.behavior, 'domain');
      expect(body.entries, [
        '+.2mdn.net',
        'adservice.google.com',
        'aod.itunes.apple.com',
      ]);
      expect(body.name, 'direct');
    });

    test('CIDR 列表 → behavior=ipcidr', () {
      final body = parseRuleProviderBody(
        _cidrPayload,
        url: 'https://example.com/rules/cncidr.txt',
      );
      expect(body!.behavior, 'ipcidr');
      expect(body.count, 3);
      expect(body.name, 'cncidr');
    });

    test('纯文本一行一条也能认，注释与空行跳过', () {
      final body = parseRuleProviderBody('''
# comment
google.com
-.github.com
''');
      expect(body!.behavior, 'domain');
      expect(body.entries, ['google.com', '-.github.com']);
      expect(body.name, isNull);
    });

    test('空内容返回 null', () {
      expect(parseRuleProviderBody('   \n\n'), isNull);
      expect(parseRuleProviderBody('payload:\n'), isNull);
    });
  });

  group('importRuleProvider 的同名节点组', () {
    test('给了 groupName → 新建 select 组，成员用传入的节点，目标指向它', () {
      final out = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(
          _domainPayload,
          url: 'https://example.com/reject.txt',
        )!,
        name: 'reject',
        target: 'PROXY',
        url: 'https://example.com/reject.txt',
        groupName: '广告拦截',
        groupMembers: ['n1', 'DIRECT'],
      );

      expect(out.groupsAdded, ['广告拦截']);
      expect(out.groupsMerged, isEmpty);
      final group = Profile.from(out.doc).group('广告拦截');
      expect(group, isNotNull);
      expect(group!.type, 'select');
      expect(group.members, ['n1', 'DIRECT']);
      expect(out.doc.plainAt(['rules']), [
        'GEOIP,CN,DIRECT',
        'RULE-SET,reject,广告拦截',
        'MATCH,PROXY',
      ]);
    });

    test('同名组已存在 → 复用不覆盖成员，记进 groupsMerged', () {
      final out = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(_cidrPayload)!,
        name: 'cncidr',
        target: 'PROXY',
        groupName: '媒体',
        groupMembers: ['n2'],
      );

      expect(out.groupsAdded, isEmpty);
      expect(out.groupsMerged, ['媒体']);
      final group = Profile.from(out.doc).group('媒体');
      expect(group!.members, ['n1']);
      expect((out.doc.plainAt(['rules']) as List).last, 'MATCH,PROXY');
      expect(
        (out.doc.plainAt(['rules']) as List).contains('RULE-SET,cncidr,媒体'),
        isTrue,
      );
    });

    test('没给 groupName → 行为不变，仍写 RULE-SET 到原目标', () {
      final out = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(_cidrPayload)!,
        name: 'cncidr',
        target: 'DIRECT',
      );

      expect(out.groupsAdded, isEmpty);
      expect(out.groupsMerged, isEmpty);
      expect(
        (out.doc.plainAt(['rules']) as List).contains('RULE-SET,cncidr,DIRECT'),
        isTrue,
      );
    });
  });

  group('importRuleProvider', () {
    test('带 URL → http provider + RULE-SET 插到 MATCH 之前', () {
      final out = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(
          _domainPayload,
          url: 'https://example.com/direct.txt',
        )!,
        name: 'direct',
        target: 'PROXY',
        url: 'https://example.com/direct.txt',
      );

      final provider =
          (out.doc.plainAt(['rule-providers']) as Map)['direct'] as Map;
      expect(provider['type'], 'http');
      expect(provider['behavior'], 'domain');
      expect(provider['url'], 'https://example.com/direct.txt');
      expect(provider['path'], './ruleset/direct.yaml');
      expect(provider['interval'], 86400);

      final rules = Profile.from(out.doc).rules.map((r) => r.raw).toList();
      expect(rules, [
        'GEOIP,CN,DIRECT',
        'RULE-SET,direct,PROXY',
        'MATCH,PROXY',
      ]);
      expect(out.rulesAdded, 1);
      expect(out.providersAdded, ['rule-providers/direct']);
    });

    test('没有 URL → inline provider，条目直接落在配置里', () {
      final out = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(_cidrPayload)!,
        name: 'cncidr',
        target: 'DIRECT',
      );

      final provider =
          (out.doc.plainAt(['rule-providers']) as Map)['cncidr'] as Map;
      expect(provider['type'], 'inline');
      expect(provider['behavior'], 'ipcidr');
      expect(provider['payload'], [
        '1.0.1.0/24',
        '1.0.2.0/23',
        '223.255.252.0/23',
      ]);

      final rules = Profile.from(out.doc).rules.map((r) => r.raw).toList();
      expect(rules.contains('RULE-SET,cncidr,DIRECT'), isTrue);
    });

    test('目标组不存在时自动建 select 组', () {
      final out = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(_domainPayload)!,
        name: 'reject',
        target: '广告拦截',
      );

      final profile = Profile.from(out.doc);
      expect(profile.group('广告拦截'), isNotNull);
      expect(out.targetGroupsCreated, ['广告拦截']);
      expect(
        profile.rules.map((r) => r.raw).toList(),
        contains('RULE-SET,reject,广告拦截'),
      );
    });

    test('重复导入同一规则集只提示、不重复写规则', () {
      final first = importRuleProvider(
        _doc(),
        body: parseRuleProviderBody(_domainPayload)!,
        name: 'direct',
        target: 'PROXY',
        url: 'https://example.com/direct.txt',
      );
      final second = importRuleProvider(
        first.doc,
        body: parseRuleProviderBody(_domainPayload)!,
        name: 'direct',
        target: 'PROXY',
        url: 'https://example.com/direct.txt',
      );

      expect(second.providersAdded, isEmpty);
      expect(second.rulesAdded, 0);
      expect(second.rulesSkipped, 1);
      expect(second.warnings.first, contains('已有'));
      final ruleSetCount = Profile.from(second.doc).rules
          .where((r) => r.raw == 'RULE-SET,direct,PROXY')
          .length;
      expect(ruleSetCount, 1);
    });
  });
}
