import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _withAutoGroup = '''mixed-port: 7890
mode: rule
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
      - REJECT
  - name: OTHER
    type: select
    proxies:
      - n1
rules:
  - MATCH,DEFAULT
''';

const _withoutGroups = '''mixed-port: 7890
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
rules:
  - MATCH,DIRECT
''';

const _noNodes = '''mixed-port: 7890
proxies: []
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,DEFAULT
''';

YamlDoc _load(String text) {
  final doc = YamlDoc.parse(text);
  expect(doc.isValid, isTrue, reason: '${doc.error}');
  return doc;
}

Map<String, Object?> _node(String name, String host) => {
  'name': name,
  'type': 'vless',
  'server': host,
  'port': 443,
  'uuid': '66666666-7777-8888-9999-000000000000',
};

void main() {
  test('新模板没有节点时先不写「自动选择」，打开编辑器也不落盘', () {
    final starter = _load(ProfileStore.starterConfig(name: '模板'));
    expect(Profile.from(starter).groups.map((e) => e.name), [
      kDefaultGroupName,
    ]);
    expect(
      identical(ConfigOps.ensureAutoGroup(starter).text, starter.text),
      isTrue,
    );
  });

  test('有节点的老配置补建：url-test / tolerance / 成员=全部节点', () {
    final once = ConfigOps.ensureAutoGroup(_load(_withAutoGroup));
    final profile = Profile.from(once);
    expect(profile.groups.map((e) => e.name), [
      kDefaultGroupName,
      kAutoGroupName,
      'OTHER',
    ]);

    final auto = profile.group(kAutoGroupName)!;
    expect(auto.type, 'url-test');
    expect(auto.raw['url'], kAutoGroupTestUrl);
    expect(auto.raw['interval'], kAutoGroupInterval);
    expect(auto.raw['tolerance'], kAutoGroupTolerance);
    expect(auto.members, ['n1']);

    final twice = ConfigOps.ensureAutoGroup(once);
    expect(identical(twice.text, once.text), isTrue);
  });

  test('没有节点但规则指向「自动选择」时也要建组（否则规则失效）', () {
    final doc = _load(
      _noNodes.replaceFirst('MATCH,DEFAULT', 'MATCH,$kAutoGroupName'),
    );
    final profile = Profile.from(ConfigOps.ensureAutoGroup(doc));
    final auto = profile.group(kAutoGroupName);
    expect(auto, isNotNull);
    expect(auto!.members, isEmpty);
  });

  test('没有任何组也能补建', () {
    final profile = Profile.from(
      ConfigOps.ensureAutoGroup(_load(_withoutGroups)),
    );
    expect(profile.groups.map((e) => e.name), [kAutoGroupName]);
    expect(profile.group(kAutoGroupName)!.members, ['n1']);
  });

  test('新节点同时进 DEFAULT（内置之前）与「自动选择」（追加）', () {
    final doc = ConfigOps.ensureAutoGroup(_load(_withAutoGroup));
    final next = ConfigOps.addProxy(doc, _node('n2', 'b.example.com'));
    final profile = Profile.from(next);
    expect(profile.group(kDefaultGroupName)!.members, [
      'n1',
      'n2',
      'DIRECT',
      'REJECT',
    ]);
    expect(profile.group(kAutoGroupName)!.members, ['n1', 'n2']);
  });

  test('删节点后「自动选择」跟着少一个，空成员时不删组', () {
    final doc = ConfigOps.ensureAutoGroup(_load(_withAutoGroup));
    final next = ConfigOps.deleteProxy(doc, 'n1');
    final profile = Profile.from(next);
    expect(profile.group(kAutoGroupName)!.members, isEmpty);
    // 已经有这个组就先留着，避免每次加删节点都重建、丢掉 tolerance 等设置。
    expect(profile.group(kAutoGroupName), isNotNull);
  });

  test('旧版本「自动选择」里的 DIRECT 会被同步掉', () {
    const legacy = '''mixed-port: 7890
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - n1
      - DIRECT
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - n1
      - DIRECT
rules:
  - MATCH,DEFAULT
''';
    final profile = Profile.from(ConfigOps.ensureAutoGroup(_load(legacy)));
    expect(profile.group(kAutoGroupName)!.members, ['n1']);
  });
}
