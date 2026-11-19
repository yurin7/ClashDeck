import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/delay_targets.dart';

void main() {
  test('按声明顺序取 proxies 的名字', () {
    final doc = YamlDoc.parse('''
proxies:
  - {name: 日本 REALITY, type: vless, server: a.example, port: 443}
  - {name: 美国 gRPC, type: trojan, server: b.example, port: 443}
''');
    expect(delayTargetsFrom(doc), ['日本 REALITY', '美国 gRPC']);
  });

  test('没有 proxies 或格式不对时返回空', () {
    expect(delayTargetsFrom(YamlDoc.parse('proxies: nope')), isEmpty);
    expect(delayTargetsFrom(YamlDoc.parse('')), isEmpty);
  });

  test('跳过没有名字或名字为空的项', () {
    final doc = YamlDoc.parse('''
proxies:
  - {type: ss, server: a.example, port: 1}
  - {name: '', type: ss, server: b.example, port: 1}
  - {name: OK, type: ss, server: c.example, port: 1}
''');
    expect(delayTargetsFrom(doc), ['OK']);
  });
}
