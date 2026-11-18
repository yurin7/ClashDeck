import 'dart:io';

import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets.dart';

const String _yaml = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - 香港 01
      - DIRECT
  - name: OTHER
    type: select
    proxies:
      - 香港 01
      - DIRECT
rules:
  - DOMAIN-SUFFIX,a.com,PROXY
  - MATCH,PROXY
''';

Future<EditorState> _pumpBoard(
  WidgetTester tester, {
  String yaml = _yaml,
}) async {
  tester.view.physicalSize = const Size(1080, 4800);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);

  final state = EditorState.fromText(yaml, fileName: 't.yaml');
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: Scaffold(body: ProxyBoard(state: state)),
    ),
  );
  await tester.pump(const Duration(milliseconds: 100));
  return state;
}

void main() {
  testWidgets('组卡的 ⋮ 直接打开编辑弹窗，没有菜单', (tester) async {
    await _pumpBoard(tester);

    await tester.tap(find.byTooltip('组设置').first);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byKey(const ValueKey('edit-dialog')), findsOneWidget);
    expect(find.text('编辑策略组'), findsOneWidget);
    expect(find.text('编辑组'), findsNothing);
    expect(find.text('删除组'), findsNothing);
  });

  testWidgets('策略组左滑露出删除，确认后组消失', (tester) async {
    final state = await _pumpBoard(tester);
    expect(state.profile.group('OTHER'), isNotNull);

    final row = find.ancestor(
      of: find.text('OTHER'),
      matching: find.byType(SlidableRow),
    );
    await tester.ensureVisible(row);
    await tester.drag(row, const Offset(-120, 0));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.textContaining('删除策略组「OTHER」'), findsOneWidget);

    await tester.tap(find.text('删除').last);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(state.profile.group('OTHER'), isNull);
  });

  testWidgets('「本组规则」胶囊拖到另一个组，规则改挂过去', (tester) async {
    final state = await _pumpBoard(tester);

    // 展开 PROXY 的「本组规则」。
    await tester.tap(find.text('本组规则 2'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final chip = find.byType(RuleChip).first;
    await tester.ensureVisible(chip);
    final from = tester.getCenter(chip);
    final to = tester.getCenter(find.text('OTHER'));

    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 600));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump(const Duration(milliseconds: 400));

    final rule = state.profile.rules.firstWhere((r) => r.payload == 'a.com');
    expect(rule.target, 'OTHER');
  });

  testWidgets('节点拖进只有 DIRECT 的组：DIRECT 沉底且自动切到节点', (tester) async {
    const yaml = '''
mixed-port: 7890
proxies:
  - name: 香港 01
    type: vless
    server: example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - 香港 01
      - DIRECT
  - name: ONLYDIRECT
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,PROXY
''';
    final state = await _pumpBoard(tester, yaml: yaml);
    expect(state.profile.group('ONLYDIRECT')!.members, ['DIRECT']);

    final chip = find.widgetWithText(NodeChip, '香港 01').first;
    await tester.ensureVisible(chip);
    final from = tester.getCenter(chip);
    final to = tester.getCenter(find.text('ONLYDIRECT'));

    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.moveTo(to);
    await tester.pump(const Duration(milliseconds: 200));
    await gesture.up();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    // 成员归一化：节点在前、DIRECT 沉底；并顺手把本组出口切到新节点。
    expect(state.profile.group('ONLYDIRECT')!.members, ['香港 01', 'DIRECT']);
    expect(find.textContaining('已加入并切换到'), findsOneWidget);
  });

  test('端到端：新建组加入 DIRECT，写盘后重开仍在', () async {
    final dir = Directory.systemTemp.createTempSync('clashdeck-e2e-');
    addTearDown(() => dir.deleteSync(recursive: true));
    final store = ProfileStore(dir);

    final created = await store.create(
      '往返',
      ProfileStore.starterConfig(name: '往返'),
    );
    await store.write(
      created.fileName,
      () {
        var doc = YamlDoc.parse(ProfileStore.starterConfig(name: '往返'));
        doc = ConfigOps.addGroup(doc, {'name': '测试组', 'type': 'select'});
        doc = ConfigOps.addGroupMember(doc, '测试组', 'DIRECT');
        return doc;
      }().text,
    );
    await store.writeMeta(created.fileName, {
      'app': {
        'groupNodes': {'测试组': 'DIRECT'},
      },
    });

    // 模拟重开 App：重新读盘、重新解析、重新读 sidecar。
    final text = await store.read(created.fileName);
    expect(text, isNotNull);
    final profile = Profile.from(YamlDoc.parse(text));
    final group = profile.group('测试组');
    expect(group, isNotNull);
    expect(group!.members, contains('DIRECT'));

    final meta = await store.readMeta(created.fileName);
    final app = meta['app'];
    expect(app, isA<Map>());
    expect((app as Map)['groupNodes'], containsPair('测试组', 'DIRECT'));
  });
}
