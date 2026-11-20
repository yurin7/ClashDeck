import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/edit/member_picker.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _yaml = r'''mixed-port: 7890
proxies:
  - name: A
    type: ss
    server: 127.0.0.1
    port: 8899
    cipher: aes-128-gcm
    password: p
  - name: B
    type: ss
    server: 127.0.0.1
    port: 8898
    cipher: aes-128-gcm
    password: p
  - name: C
    type: ss
    server: 127.0.0.1
    port: 8897
    cipher: aes-128-gcm
    password: p
  - name: D
    type: ss
    server: 127.0.0.1
    port: 8896
    cipher: aes-128-gcm
    password: p
  - name: E
    type: ss
    server: 127.0.0.1
    port: 8895
    cipher: aes-128-gcm
    password: p
proxy-groups:
  - name: 链式
    type: relay
    proxies:
      - C
      - A
      - B
rules:
  - MATCH,链式
''';

void main() {
  final profile = Profile.from(YamlDoc.parse(_yaml));

  group('orderNamesByNodeList', () {
    test('点选 [E, D] 按节点列表顺序变成 [D, E]', () {
      expect(orderNamesByNodeList(profile, ['E', 'D']), ['D', 'E']);
    });

    test('不在节点列表里的名字保持相对顺序排在最后', () {
      expect(orderNamesByNodeList(profile, ['E', 'X', 'D', 'Y']), [
        'D',
        'E',
        'X',
        'Y',
      ]);
    });

    test('空输入返回空列表，重复名去重保留首次位置', () {
      expect(orderNamesByNodeList(profile, const []), isEmpty);
      expect(orderNamesByNodeList(profile, ['D', 'D', 'E']), ['D', 'E']);
    });
  });

  group('链式批量加入保持节点列表顺序', () {
    test('链 C,A,B 批量先点 E 再点 D，追加为 C,A,B,D,E', () {
      var doc = YamlDoc.parse(_yaml);
      final names = orderNamesByNodeList(profile, ['E', 'D']);
      for (final name in names) {
        doc = ConfigOps.addGroupMember(doc, '链式', name, appendToEnd: true);
      }
      expect(Profile.from(doc).group('链式')!.members, ['C', 'A', 'B', 'D', 'E']);
    });
  });
}
