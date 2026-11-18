import 'dart:io';

import 'package:clashdeck/core/edit/group_selection.dart';
import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _yaml = '''
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
  - name: n2
    type: vless
    server: b.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - n1
      - n2
  - name: 空组
    type: select
    proxies: []

rules:
  - MATCH,PROXY
''';

GroupEntry _group(Profile profile, String name) =>
    profile.groups.firstWhere((group) => group.name == name);

void main() {
  late Profile profile;

  setUp(() {
    profile = Profile.from(YamlDoc.parse(_yaml));
  });

  test('记住的选择仍存在时优先', () {
    expect(
      selectedInGroup(
        {'PROXY': 'n2'},
        _group(profile, 'PROXY'),
        proxyOrder: [for (final proxy in profile.proxies) proxy.name],
      ),
      'n2',
    );
  });

  test('没记住时优先节点（即使 DIRECT 排在前面）', () {
    final doc = YamlDoc.parse('''
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
proxy-groups:
  - name: PROXY
    type: select
    proxies: [DIRECT, n1]
rules:
  - MATCH,PROXY
''');
    final builtinsFirst = Profile.from(doc);
    expect(
      selectedInGroup(
        const <String, String>{},
        _group(builtinsFirst, 'PROXY'),
        proxyOrder: [for (final proxy in builtinsFirst.proxies) proxy.name],
      ),
      'n1',
    );
  });

  test('记住的成员被删掉后回落到自动选择；空组没有可选成员', () {
    // 旧 sidecar 里记着已被移除的 n1：不能再当成有效选择，否则删光成员后
    // 重新加节点会没有任何 chip 高亮。
    expect(selectedInGroup({'空组': 'n1'}, _group(profile, '空组')), isNull);
    expect(
      selectedInGroup(const <String, String>{}, _group(profile, '空组')),
      isNull,
    );
  });

  test('快照覆盖所有有成员的组，过期选择自动回落', () {
    expect(groupSelectionSnapshot(profile, const {'PROXY': 'n2'}), {
      'PROXY': 'n2',
    });
    expect(groupSelectionSnapshot(profile, const {'PROXY': '已删除'}), {
      'PROXY': 'n1',
    });
  });

  test('groupNodesOf 只接收字符串键值对', () {
    expect(
      groupNodesOf({
        'app': {
          'groupNodes': {'PROXY': 'n1', '坏键': 42},
        },
      }),
      {'PROXY': 'n1'},
    );
    expect(groupNodesOf(const <String, Object?>{}), isEmpty);
    expect(groupNodesOf({'app': 'not-a-map'}), isEmpty);
  });

  test('sidecar 往返：组内选择写回后重开仍在，默认选择不被覆盖', () async {
    final tmp = Directory.systemTemp.createTempSync('clashdeck_selection_io');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final store = ProfileStore(tmp);
    final created = await store.create('demo', _yaml);

    // 新建配置默认 DEFAULT → DIRECT。
    expect(groupNodesOf(await store.readMeta(created.fileName)), {
      'DEFAULT': 'DIRECT',
    });

    final meta = await store.readMeta(created.fileName);
    await store.writeMeta(created.fileName, withGroupNode(meta, 'PROXY', 'n2'));

    // 「重开」= 重新从磁盘读 meta。
    expect(groupNodesOf(await store.readMeta(created.fileName)), {
      'DEFAULT': 'DIRECT',
      'PROXY': 'n2',
    });
  });

  test('withGroupNode 只动 app.groupNodes，其它键原样保留', () {
    final meta = <String, Object?>{
      'subscriptionUrl': 'https://example.com/sub',
      'app': {'globalNode': 'DIRECT', 'autoSave': true},
    };

    final next = withGroupNode(meta, 'PROXY', 'n2');

    expect(next['subscriptionUrl'], 'https://example.com/sub');
    final app = next['app']! as Map;
    expect(app['globalNode'], 'DIRECT');
    expect(app['autoSave'], true);
    expect(groupNodesOf(next), {'PROXY': 'n2'});
    // 不改传入的 map。
    expect((meta['app']! as Map)['groupNodes'], isNull);
  });
}
