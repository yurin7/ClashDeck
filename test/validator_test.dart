import 'package:clashdeck/core/validate/validator.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

ValidationReport run(String text) =>
    ConfigValidator.validate(YamlDoc.parse(text));

List<String> codes(String text) => run(text).issues.map((e) => e.code).toList();

const clean = r'''
mixed-port: 7890
mode: rule
proxies:
  - name: HK-01
    type: vless
    server: hk.example.com
    port: 443
    uuid: u-u-i-d
proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK-01]
rules:
  - DOMAIN-SUFFIX,google.com,PROXY
  - MATCH,PROXY
''';

void main() {
  test('干净配置没有任何问题', () {
    final report = run(clean);
    expect(report.isClean, isTrue, reason: report.issues.join('; '));
    expect(report.canSubmit, isTrue);
  });

  group('YAML 与端口', () {
    test('语法错误直接短路', () {
      final report = run('proxies:\n  - name: [unclosed\n');
      expect(report.errors.single.code, 'yaml-parse');
    });

    test('端口越界', () {
      expect(codes('mixed-port: 70000\n'), contains('bad-port'));
      expect(codes('port: "abc"\n'), contains('bad-port'));
    });
  });

  group('节点', () {
    test('重名', () {
      final text = '''
proxies:
  - {name: A, type: vless, server: a, port: 1, uuid: u}
  - {name: A, type: vless, server: b, port: 1, uuid: u}
''';
      expect(codes(text), contains('duplicate-proxy-name'));
    });

    test('缺 type', () {
      expect(
        codes('proxies:\n  - name: A\n    server: a\n'),
        contains('proxy-missing-type'),
      );
    });

    test('缺 server / port', () {
      final c = codes('proxies:\n  - name: A\n    type: vless\n    uuid: u\n');
      expect(c, containsAll(['proxy-missing-server', 'proxy-missing-port']));
    });

    test('vless 缺 uuid', () {
      final c = codes(
        'proxies:\n  - name: A\n    type: vless\n    server: a.example.com\n    port: 443\n',
      );
      expect(c, contains('proxy-missing-uuid'));
    });

    test('trojan 缺 password', () {
      final c = codes(
        'proxies:\n  - name: A\n    type: trojan\n    server: a\n    port: 443\n',
      );
      expect(c, contains('proxy-missing-password'));
    });

    test('wireguard 不要求 server', () {
      final c = codes(
        'proxies:\n  - name: W\n    type: wireguard\n    private-key: k\n',
      );
      expect(c, isNot(contains('proxy-missing-server')));
      expect(c, isNot(contains('wireguard-missing-key')));
    });

    test('dialer-proxy 悬空', () {
      final c = codes('''
proxies:
  - name: A
    type: vless
    server: a
    port: 1
    uuid: u
    dialer-proxy: NOT-THERE
''');
      expect(c, contains('dangling-dialer-proxy'));
    });
  });

  group('策略组', () {
    test('重名', () {
      final c = codes('''
proxy-groups:
  - {name: G, type: select}
  - {name: G, type: select}
''');
      expect(c, containsAll(['duplicate-group-name', 'empty-select-group']));
    });

    test('缺 type', () {
      expect(
        codes('proxy-groups:\n  - name: G\n'),
        contains('group-missing-type'),
      );
    });

    test('未知 type 是警告', () {
      final report = run('proxy-groups:\n  - name: G\n    type: weird\n');
      final issue = report.issues.firstWhere(
        (e) => e.code == 'unknown-group-type',
      );
      expect(issue.severity, IssueSeverity.warning);
    });

    test('成员不存在是警告；computed 组降级为提示', () {
      final warn = run('''
proxy-groups:
  - name: G
    type: select
    proxies: [GHOST]
''');
      expect(
        warn.issues.firstWhere((e) => e.code == 'dangling-member').severity,
        IssueSeverity.warning,
      );

      final info = run('''
proxy-groups:
  - name: G
    type: select
    include-all: true
    proxies: [GHOST]
''');
      expect(
        info.issues.firstWhere((e) => e.code == 'dangling-member').severity,
        IssueSeverity.info,
      );
    });

    test('use 引用未定义的 provider', () {
      expect(
        codes('proxy-groups:\n  - name: G\n    type: select\n    use: [P1]\n'),
        contains('unknown-provider'),
      );
      expect(
        codes('''
proxy-providers:
  P1:
    type: http
    url: http://x
proxy-groups:
  - name: G
    type: select
    use: [P1]
'''),
        isNot(contains('unknown-provider')),
      );
    });

    test('组与节点同名', () {
      final c = codes('''
proxies:
  - {name: X, type: vless, server: a, port: 1, uuid: u}
proxy-groups:
  - {name: X, type: select, proxies: [X]}
''');
      expect(c, contains('name-shadow'));
    });
  });

  group('规则', () {
    test('缺目标', () {
      expect(
        codes('rules:\n  - DOMAIN-SUFFIX,google.com\n'),
        contains('rule-missing-target'),
      );
    });

    test('目标不存在', () {
      expect(
        codes('rules:\n  - DOMAIN-SUFFIX,google.com,NOPE\n'),
        contains('unknown-rule-target'),
      );
    });

    test('内置策略与节点都算合法目标', () {
      final c = codes('''
proxies:
  - {name: N, type: vless, server: a, port: 1, uuid: u}
rules:
  - DOMAIN,a.com,DIRECT
  - DOMAIN,b.com,N
  - MATCH,REJECT
''');
      expect(c, isNot(contains('unknown-rule-target')));
      expect(c, isNot(contains('terminal-rule-not-last')));
    });

    test('MATCH 不在最后', () {
      final c = codes('''
rules:
  - MATCH,DIRECT
  - DOMAIN,a.com,DIRECT
''');
      expect(c, contains('terminal-rule-not-last'));
    });

    test('多条 MATCH', () {
      final c = codes('rules:\n  - MATCH,DIRECT\n  - MATCH,REJECT\n');
      expect(c, contains('multiple-terminal-rules'));
    });

    test('没有兜底规则', () {
      expect(
        codes('rules:\n  - DOMAIN,a.com,DIRECT\n'),
        contains('no-terminal-rule'),
      );
    });
  });

  test('mode 未知', () {
    expect(codes('mode: turbo\n'), contains('unknown-mode'));
  });

  test('问题排序：错误在前', () {
    final report = run('''
mixed-port: 99999
mode: turbo
rules:
  - MATCH,DIRECT
  - DOMAIN,a.com,DIRECT
''');
    expect(report.hasErrors, isTrue);
    final firstWarning = report.issues.indexWhere((e) => !e.isError);
    final lastError = report.issues.lastIndexWhere((e) => e.isError);
    expect(lastError, lessThan(firstWarning));
    expect(report.canSubmit, isFalse);
  });
}
