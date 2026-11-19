import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/ui/sheets/node_picker_sheet.dart';

const _yaml = '''
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 1, cipher: aes-128-gcm, password: x}
  - {name: b, type: ss, server: 1.1.1.1, port: 2, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: chain, type: relay, proxies: [a, b]}
rules:
  - MATCH,chain
''';

void main() {
  test('链式代理的候选列表不包含系统策略段', () {
    final profile = Profile.from(YamlDoc.parse(_yaml));
    final entries = nodePickerEntries(
      profile,
      groupName: 'chain',
      members: const ['a', 'b'],
      includeBuiltins: false,
    );
    expect(
      entries.where((entry) => entry.section == NodePickerSection.builtin),
      isEmpty,
    );
    expect(
      entries.where((entry) => entry.section == NodePickerSection.node),
      isNotEmpty,
    );
  });

  test('普通组仍保留系统策略段', () {
    final profile = Profile.from(YamlDoc.parse(_yaml));
    final entries = nodePickerEntries(
      profile,
      groupName: 'chain',
      members: const ['a', 'b'],
    );
    expect(
      entries.where((entry) => entry.section == NodePickerSection.builtin),
      isNotEmpty,
    );
  });
}
