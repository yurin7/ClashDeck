import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _relayYaml = '''
mixed-port: 7890
proxies:
  - {name: A, type: ss, server: a.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: B, type: ss, server: b.example.com, port: 443, cipher: aes-128-gcm, password: p}
  - {name: C, type: ss, server: c.example.com, port: 443, cipher: aes-128-gcm, password: p}
proxy-groups:
  - name: 链式
    type: relay
    proxies: [A, B, C]
rules:
  - MATCH,链式
''';

List<String> _members(YamlDoc doc) => Profile.from(doc).group('链式')!.members;

void main() {
  test('relay 成员删掉再加回时追加到链尾，不按 proxies 顺序重排', () {
    var doc = YamlDoc.parse(_relayYaml);
    expect(_members(doc), ['A', 'B', 'C']);

    doc = ConfigOps.removeGroupMember(doc, '链式', 'A');
    expect(_members(doc), ['B', 'C']);

    doc = ConfigOps.addGroupMember(doc, '链式', 'A', appendToEnd: true);
    expect(_members(doc), ['B', 'C', 'A']);
  });

  test('relay 新成员同样追加到链尾', () {
    var doc = YamlDoc.parse(_relayYaml);
    doc = ConfigOps.addGroupMember(doc, '链式', 'B');
    expect(_members(doc), ['A', 'B', 'C']);

    doc = ConfigOps.removeGroupMember(doc, '链式', 'B');
    doc = ConfigOps.addGroupMember(doc, '链式', 'B', appendToEnd: true);
    expect(_members(doc), ['A', 'C', 'B']);
  });

  test('moveGroupMember 的 to 是 gap 索引，链内换位后顺序符合拖拽预期', () {
    final doc = YamlDoc.parse(_relayYaml);

    // B 拖到 C 后面的间隙（gap 3）→ A,C,B。
    final moveBack = ConfigOps.moveGroupMember(doc, '链式', 1, 3);
    expect(_members(moveBack), ['A', 'C', 'B']);

    // C 拖到最前（gap 0）→ C,A,B。
    final moveFront = ConfigOps.moveGroupMember(doc, '链式', 2, 0);
    expect(_members(moveFront), ['C', 'A', 'B']);

    // 落在自己原来的间隙：纯空操作，文本都不变。
    final noop = ConfigOps.moveGroupMember(doc, '链式', 1, 1);
    expect(noop.text, doc.text);
  });
}
