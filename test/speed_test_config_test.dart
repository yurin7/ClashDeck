import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/speed_test_config.dart';

const _docText = r'''
mixed-port: 7897
proxies:
  - {name: alpha, type: ss, server: 1.2.3.4, port: 443, cipher: aes-128-gcm, password: pw}
  - {name: beta, type: ss, server: 5.6.7.8, port: 443, cipher: aes-128-gcm, password: pw}
proxy-groups:
  - {name: 其它组, type: select, proxies: [beta]}
rules:
  - MATCH,其它组
''';

void main() {
  test('节点不在任何策略组里也能生成测速配置', () {
    final doc = YamlDoc.parse(_docText);
    final text = buildSpeedTestConfig(doc, nodeName: 'alpha');

    expect(text, contains('name: speed-probe'));
    expect(text, contains('type: select'));
    expect(text, contains(searchNodeName('alpha')));
    expect(text, contains('MATCH,speed-probe'));
  });

  test('只保留目标节点，并关闭 DNS、静默日志、复用代理端口', () {
    final doc = YamlDoc.parse(_docText);
    final text = buildSpeedTestConfig(doc, nodeName: 'alpha');

    expect(text, contains('alpha'));
    expect(text, isNot(contains('beta')));
    expect(text, contains('mixed-port: 7897'));
    expect(text, contains('log-level: silent'));
    expect(text, contains('enable: false'));
  });

  test('找不到节点时给出中文原因', () {
    final doc = YamlDoc.parse(_docText);
    expect(
      () => buildSpeedTestConfig(doc, nodeName: 'missing'),
      throwsA(
        isA<SpeedTestConfigException>().having(
          (error) => error.message,
          'message',
          '找不到节点：missing',
        ),
      ),
    );
  });

  test('配置里没有节点时给出中文原因', () {
    final doc = YamlDoc.parse('mixed-port: 7890\n');
    expect(
      () => buildSpeedTestConfig(doc, nodeName: 'alpha'),
      throwsA(
        isA<SpeedTestConfigException>().having(
          (error) => error.message,
          'message',
          '配置里还没有节点',
        ),
      ),
    );
  });
}

/// 节点在序列化后可能是 `name: alpha` 或 `name: "alpha"`，两种都接受。
String searchNodeName(String name) => name;
