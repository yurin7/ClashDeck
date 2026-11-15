import 'package:clashdeck/core/model/config_summary.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ConfigSummary.fromText', () {
    test('正常配置统计节点、策略组、规则与 mode', () {
      const text = '''
mode: global
proxies:
  - name: 香港 01
    type: vless
    server: hk.example.com
    port: 443
  - name: 日本 01
    type: ss
    server: jp.example.com
    port: 8388
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - 香港 01
      - 日本 01
rules:
  - DOMAIN-SUFFIX,example.com,PROXY
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
''';
      final summary = ConfigSummary.fromText(text);

      expect(summary.valid, isTrue);
      expect(summary.error, isNull);
      expect(summary.proxies, 2);
      expect(summary.groups, 1);
      expect(summary.rules, 3);
      expect(summary.mode, 'global');
    });

    test('空配置（proxies: []）计数全为 0，mode 缺省为 rule', () {
      const text = 'proxies: []\nproxy-groups: []\nrules: []\n';
      final summary = ConfigSummary.fromText(text);

      expect(summary.valid, isTrue);
      expect(summary.proxies, 0);
      expect(summary.groups, 0);
      expect(summary.rules, 0);
      expect(summary.mode, 'rule');
    });

    test('非法 YAML 返回 valid=false 与错误信息，且不抛异常', () {
      const text = 'proxies: [\n  - {name: broken\n';
      late ConfigSummary summary;

      expect(() => summary = ConfigSummary.fromText(text), returnsNormally);
      expect(summary.valid, isFalse);
      expect(summary.error, isNotNull);
      expect(summary.error, isNotEmpty);
      expect(summary.proxies, 0);
      expect(summary.groups, 0);
      expect(summary.rules, 0);
      expect(summary.mode, isNull);
    });

    test('只有规则没有节点时也能统计', () {
      const text = '''
mode: direct
rules:
  - MATCH,DIRECT
''';
      final summary = ConfigSummary.fromText(text);

      expect(summary.valid, isTrue);
      expect(summary.proxies, 0);
      expect(summary.groups, 0);
      expect(summary.rules, 1);
      expect(summary.mode, 'direct');
    });

    test('根节点不是映射时 valid=false，不抛异常', () {
      const text = '- 第一项\n- 第二项\n';
      late ConfigSummary summary;

      expect(() => summary = ConfigSummary.fromText(text), returnsNormally);
      expect(summary.valid, isFalse);
      expect(summary.mode, isNull);
      expect(summary.rules, 0);
    });

    test('unknown 占位值保持 0 / 未校验', () {
      expect(ConfigSummary.unknown.proxies, 0);
      expect(ConfigSummary.unknown.groups, 0);
      expect(ConfigSummary.unknown.rules, 0);
      expect(ConfigSummary.unknown.mode, isNull);
      expect(ConfigSummary.unknown.valid, isFalse);
      expect(ConfigSummary.unknown.error, isNull);
    });
  });
}
