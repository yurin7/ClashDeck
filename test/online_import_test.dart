import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/edit/import_rules.dart';
import 'package:clashdeck/core/edit/online_import.dart';
import 'package:clashdeck/core/edit/rule_presets.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/rule_cache.dart';
import 'package:flutter_test/flutter_test.dart';

const _base = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
rule-providers:
  loyal-reject:
    type: http
    behavior: domain
    url: https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt
    path: ./ruleset/loyal-reject.yaml
    interval: 86400
rules:
  - RULE-SET,loyal-reject,REJECT
  - MATCH,DEFAULT
''';

RulePreset _preset(String id) => <RulePreset>[
  ...kLoyalRulesPresets,
  ...kAclRulesPresets,
].firstWhere((preset) => preset.id == id);

RuleProviderBody _body(List<String> entries) =>
    RuleProviderBody(entries: entries, behavior: 'domain');

void main() {
  group('planOnlineImport', () {
    test('已存在的规则集算更新，新 id 算新建，目标统一 DEFAULT', () async {
      final doc = YamlDoc.parse(_base);
      final plan = await planOnlineImport(doc, [
        FetchedPreset(
          preset: _preset('loyal-reject'),
          body: _body(['DOMAIN-SUFFIX,a.com']),
          text: 'DOMAIN-SUFFIX,a.com',
        ),
        FetchedPreset(
          preset: _preset('acl-openai'),
          body: _body(['DOMAIN-SUFFIX,b.com']),
          text: 'DOMAIN-SUFFIX,b.com',
        ),
      ]);

      expect(plan.plan.updatedProviders, ['loyal-reject']);
      expect(plan.plan.newProviders, ['acl-openai']);
      // 两条都会落地，各自对应一条 RULE-SET 规则。
      expect(plan.plan.rulesToAdd, 2);
      expect(plan.plan.skippedRules, 0);
      expect(plan.toApply.map((item) => item.preset.id), [
        'loyal-reject',
        'acl-openai',
      ]);
      expect(plan.skippedIds, isEmpty);
      expect(plan.failedIds, isEmpty);
    });

    test('内容与已有缓存完全相同 → 跳过，不新建 provider', () async {
      final doc = YamlDoc.parse(_base);
      final body = _body(['DOMAIN-SUFFIX,a.com']);
      final plan = await planOnlineImport(
        doc,
        [FetchedPreset(preset: _preset('acl-apple'), body: body)],
        cachedBody: (id) async => id == 'loyal-reject'
            ? ruleCacheBody(body.entries, body.behavior)
            : null,
      );

      expect(plan.skippedIds, ['acl-apple']);
      expect(plan.toApply, isEmpty);
      expect(plan.plan.rulesToAdd, 0);
      expect(plan.plan.skippedRules, 1);
      expect(plan.plan.newProviders, isEmpty);
      expect(plan.plan.updatedProviders, isEmpty);
    });

    test('拉取失败的规则集只进 failedIds', () async {
      final plan = await planOnlineImport(YamlDoc.parse(_base), [
        FetchedPreset(preset: _preset('acl-apple'), error: '没识别出规则集内容'),
      ]);

      expect(plan.failedIds, ['acl-apple']);
      expect(plan.toApply, isEmpty);
      expect(plan.plan.rulesToAdd, 0);
      expect(plan.plan.newProviders, isEmpty);
    });
  });

  group('applyOnlineImport', () {
    test('RULE-SET 行与 provider 都落到 DEFAULT，缓存路径写成 type: file', () async {
      final doc = YamlDoc.parse(_base);
      final preview = await planOnlineImport(doc, [
        FetchedPreset(
          preset: _preset('loyal-reject'),
          body: _body(['DOMAIN-SUFFIX,a.com']),
          text: 'DOMAIN-SUFFIX,a.com',
        ),
        FetchedPreset(
          preset: _preset('acl-openai'),
          body: _body(['DOMAIN-SUFFIX,b.com']),
          text: 'DOMAIN-SUFFIX,b.com',
        ),
      ]);
      final result = applyOnlineImport(
        doc,
        preview,
        cachePathFor: (id) => '/cache/$id.yaml',
      );

      expect(result.isEmpty, isFalse);
      expect(result.failed, isEmpty);
      expect(result.failedPresets, isEmpty);
      expect(result.applied, hasLength(2));

      final profile = Profile.from(result.doc);
      final ruleSets = [
        for (final rule in profile.rules)
          if (rule.type == 'RULE-SET') rule,
      ];
      expect(
        ruleSets.map((rule) => rule.raw),
        containsAll([
          'RULE-SET,loyal-reject,DEFAULT',
          'RULE-SET,acl-openai,DEFAULT',
        ]),
      );
      // 预览说会写几条，实际就写了几条；目标一律 DEFAULT。
      expect(ruleSets, hasLength(preview.plan.rulesToAdd));
      expect(
        ruleSets.every((rule) => rule.target == kDefaultGroupName),
        isTrue,
      );
      expect(profile.rules.last.isTerminal, isTrue);

      final provider = result.doc.plainAt(['rule-providers', 'acl-openai']);
      expect(provider, isA<Map>());
      final map = provider! as Map;
      expect(map['type'], 'file');
      expect(map['path'], '/cache/acl-openai.yaml');
      expect(map.containsKey('url'), isFalse);
    });

    test('没给缓存路径时退回 http provider，规则目标仍是 DEFAULT', () async {
      final doc = YamlDoc.parse(_base);
      final preview = await planOnlineImport(doc, [
        FetchedPreset(
          preset: _preset('acl-openai'),
          body: _body(['DOMAIN-SUFFIX,b.com']),
          text: 'DOMAIN-SUFFIX,b.com',
        ),
      ]);
      final result = applyOnlineImport(doc, preview);

      final profile = Profile.from(result.doc);
      expect(
        profile.rules.map((rule) => rule.raw),
        contains('RULE-SET,acl-openai,DEFAULT'),
      );
      final map = result.doc.plainAt(['rule-providers', 'acl-openai'])! as Map;
      expect(map['type'], 'http');
      expect(map.containsKey('url'), isTrue);
    });
  });
}
