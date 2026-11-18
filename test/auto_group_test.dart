import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

const _withAutoGroup = r'''mixed-port: 7890
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

YamlDoc _load(String text) {
  final doc = YamlDoc.parse(text);
  expect(doc.isValid, isTrue, reason: '${doc.error}');
  return doc;
}

void main() {
  test('新模板自带「自动选择」组：url-test / generate_204 / 300 秒', () {
    final profile = Profile.from(_load(ProfileStore.starterConfig(name: '模板')));
    final groups = profile.groups.map((e) => e.name).toList();
    expect(groups, [kDefaultGroupName, kAutoGroupName]);

    final auto = profile.group(kAutoGroupName)!;
    expect(auto.type, 'url-test');
    expect(auto.raw['url'], kAutoGroupTestUrl);
    expect(auto.raw['interval'], kAutoGroupInterval);
    expect(auto.members, ['DIRECT']);
    expect(profile.group(kDefaultGroupName)!.type, 'select');
  });

  test('老配置补建「自动选择」：插在 DEFAULT 之后，且幂等', () {
    final doc = _load(_withAutoGroup);
    final once = ConfigOps.ensureAutoGroup(doc);
    final groups = Profile.from(once).groups.map((e) => e.name).toList();
    expect(groups, [kDefaultGroupName, kAutoGroupName, 'OTHER']);

    final auto = Profile.from(once).group(kAutoGroupName)!;
    expect(auto.type, 'url-test');
    expect(auto.members, ['n1', 'DIRECT']);

    final twice = ConfigOps.ensureAutoGroup(once);
    expect(identical(twice.text, once.text), isTrue);
  });

  test('没有任何组也能补建', () {
    final doc = _load('mixed-port: 7890\nrules:\n  - MATCH,DIRECT\n');
    final next = ConfigOps.ensureAutoGroup(doc);
    final profile = Profile.from(next);
    expect(profile.groups.map((e) => e.name), [kAutoGroupName]);
    expect(profile.group(kAutoGroupName)!.members, ['DIRECT']);
  });

  test('新节点自动进「自动选择」，并插在 DIRECT 之前', () {
    final doc = ConfigOps.ensureAutoGroup(_load(_withAutoGroup));
    final before = Profile.from(doc);
    expect(before.group(kAutoGroupName)!.members, ['n1', 'DIRECT']);

    final next = ConfigOps.addProxy(doc, {
      'name': 'n2',
      'type': 'vless',
      'server': 'b.example.com',
      'port': 443,
      'uuid': '66666666-7777-8888-9999-000000000000',
    });
    final profile = Profile.from(next);

    // 先补齐 DEFAULT，再插到自动选择的 DIRECT 之前。
    expect(
      profile.group(kDefaultGroupName)!.members,
      containsAll(<String>['DIRECT', 'REJECT', 'n2']),
    );
    expect(profile.group(kAutoGroupName)!.members, ['n1', 'n2', 'DIRECT']);
  });

  test('没有「自动选择」组时，加节点保持原样', () {
    final doc = _load('''mixed-port: 7890
proxy-groups:
  - name: ONLY
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,ONLY
''');
    final next = ConfigOps.addProxy(doc, {
      'name': 'n3',
      'type': 'vless',
      'server': 'c.example.com',
      'port': 443,
      'uuid': '77777777-7777-8888-9999-000000000000',
    });
    final profile = Profile.from(next);
    expect(profile.group(kAutoGroupName), isNull);
    expect(profile.group('ONLY')!.members, ['DIRECT']);
    expect(profile.group(kDefaultGroupName)!.members, contains('n3'));
  });
}
