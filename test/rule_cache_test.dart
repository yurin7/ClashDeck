import 'package:clashdeck/core/edit/import_rules.dart';
import 'package:clashdeck/core/net/github_mirror.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/rule_cache.dart';
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
rules:
  - MATCH,PROXY
''';

const _raw =
    'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release/reject.txt';

void main() {
  group('GithubMirror', () {
    test('raw 地址生成 jsdelivr 镜像，且镜像排在最前', () {
      final list = GithubMirror.candidates(_raw);
      expect(list, hasLength(3));
      expect(
        list.first,
        'https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt',
      );
      expect(list[1], _raw);
      expect(list[2], startsWith('https://ghproxy.net/'));
    });

    test('落盘用 jsdelivr 地址，内核运行时也能拉', () {
      expect(
        GithubMirror.preferred(_raw),
        'https://cdn.jsdelivr.net/gh/Loyalsoldier/clash-rules@release/reject.txt',
      );
    });

    test('非 raw 地址原样返回', () {
      const other = 'https://example.com/a.txt';
      expect(GithubMirror.candidates(other), [other]);
      expect(GithubMirror.preferred(other), other);
    });
  });

  group('ruleCacheBody', () {
    test('classical 也写成 payload 列表', () {
      expect(
        ruleCacheBody(<String>[
          'DOMAIN-SUFFIX,a.com',
          'DOMAIN,b.com',
        ], 'classical'),
        'payload:\n  - DOMAIN-SUFFIX,a.com\n  - DOMAIN,b.com\n',
      );
    });

    test('classical 原文会剥掉注释再转 payload', () {
      expect(
        ruleCacheBodyFromRaw(
          '# 内容：Adobe\n# 数量：34条\nDOMAIN-KEYWORD,adobe\n',
          'classical',
        ),
        'payload:\n  - DOMAIN-KEYWORD,adobe\n',
      );
    });

    test('含 # 的值要加引号', () {
      final expected = "payload:\n  - 'DOMAIN,a.com#x'\n";
      expect(ruleCacheBodyFromRaw('DOMAIN,a.com#x\n', 'classical'), expected);
    });
    test('域名类原文原样落盘', () {
      expect(
        ruleCacheBodyFromRaw('payload:\n  - a.com\n', 'domain'),
        'payload:\n  - a.com\n',
      );
    });

    test('domain / ipcidr 写成 payload 列表', () {
      expect(
        ruleCacheBody(<String>['a.com', 'b.com'], 'domain'),
        'payload:\n  - a.com\n  - b.com\n',
      );
    });
  });

  group('YamlDoc.parse', () {
    test('历史配置里被写坏的 \\/ 会被还原', () {
      const broken = 'rules:\n  - "RULE-SET,x,内网 \\/ 本机地址"\n';
      final doc = YamlDoc.parse(broken);
      expect(doc.isValid, isTrue);
      expect(doc.text.contains(r'\/'), isFalse);
      expect(doc.text, contains('内网 / 本机地址'));
    });
  });

  group('importRuleProvider(filePath:)', () {
    test('给了 filePath 就写 type: file，且不写 url', () {
      final doc = YamlDoc.parse(_base);
      final outcome = importRuleProvider(
        doc,
        body: const RuleProviderBody(
          behavior: 'domain',
          entries: <String>['a.com'],
        ),
        name: 'loyal-direct',
        target: 'PROXY',
        url: _raw,
        filePath: '/data/user/0/dev.clashdeck/files/rules/loyal-direct.yaml',
      );
      final yaml = outcome.doc.text;
      expect(yaml, contains('type: file'));
      expect(yaml, contains('/rules/loyal-direct.yaml'));
      expect(yaml.contains('url:'), isFalse);
    });

    test('已存在 http provider 会就地改成 file', () {
      var doc = YamlDoc.parse(_base);
      doc = importRuleProvider(
        doc,
        body: const RuleProviderBody(
          behavior: 'domain',
          entries: <String>['a.com'],
        ),
        name: 'loyal-direct',
        target: 'PROXY',
        url: _raw,
      ).doc;
      expect(doc.text, contains('https://cdn.jsdelivr.net/gh/'));

      final outcome = importRuleProvider(
        doc,
        body: const RuleProviderBody(
          behavior: 'domain',
          entries: <String>['a.com'],
        ),
        name: 'loyal-direct',
        target: 'PROXY',
        filePath: '/tmp/rules/loyal-direct.yaml',
      );
      final yaml = outcome.doc.text;
      expect(yaml, contains('type: file'));
      expect(yaml.contains('url:'), isFalse);
      expect(outcome.warnings.join(), contains('本地缓存'));
    });
  });
}
