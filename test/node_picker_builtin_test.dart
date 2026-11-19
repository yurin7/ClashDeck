import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/ui/sheets/node_picker_sheet.dart';

const _yaml = '''
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 1, cipher: aes-128-gcm, password: x}
  - {name: b, type: ss, server: 1.1.1.1, port: 2, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: chain, type: relay, proxies: [a, b]}
  - {name: other, type: select, proxies: [a]}
rules:
  - MATCH,chain
''';

void main() {
  test('链式代理的候选列表只有节点：不含系统策略、不含策略组', () {
    final profile = Profile.from(YamlDoc.parse(_yaml));
    final entries = nodePickerEntries(
      profile,
      groupName: 'chain',
      members: const ['a', 'b'],
      includeBuiltins: false,
      includeGroups: false,
    );
    expect(
      entries.where((entry) => entry.section == NodePickerSection.builtin),
      isEmpty,
    );
    expect(
      entries.where((entry) => entry.section == NodePickerSection.group),
      isEmpty,
    );
    expect(
      entries.where((entry) => entry.section == NodePickerSection.node),
      isNotEmpty,
    );
  });

  test('普通组仍保留系统策略与策略组两段', () {
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
    expect(
      entries.where((entry) => entry.section == NodePickerSection.group),
      isNotEmpty,
    );
  });

  testWidgets('链式代理面板只渲染「节点」段', (tester) async {
    final profile = Profile.from(YamlDoc.parse(_yaml));
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: TextButton(
                onPressed: () => showNodePickerSheet(
                  context,
                  profile: profile,
                  groupName: 'chain',
                  members: const ['a', 'b'],
                  includeBuiltins: false,
                  includeGroups: false,
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('选择要加入的节点'), findsOneWidget);
    expect(find.text('节点'), findsOneWidget);
    expect(find.text('系统策略'), findsNothing);
    expect(find.text('策略组'), findsNothing);
    expect(find.text('搜索节点'), findsOneWidget);
  });
}
