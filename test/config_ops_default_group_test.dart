import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

YamlDoc _doc(String text) => YamlDoc.parse(text);

const _twoNodes = '''
proxies:
  - name: a
    type: ss
    server: a.example.com
    port: 443
    cipher: aes-128-gcm
    password: x
  - name: b
    type: ss
    server: b.example.com
    port: 443
    cipher: aes-128-gcm
    password: y

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - a

rules:
  - MATCH,PROXY
''';

void main() {
  test('默认组名字是 DEFAULT', () {
    expect(kDefaultGroupName, 'DEFAULT');
  });

  test('起始配置自带 DEFAULT 组，且规则指向它', () {
    final doc = _doc(ProfileStore.starterConfig());
    final profile = Profile.from(doc);
    final group = profile.group(kDefaultGroupName);
    expect(group, isNotNull);
    expect(group!.type, 'select');
    expect(group.members, containsAll(<String>['DIRECT', 'REJECT']));
    final last = profile.rules.last;
    expect(last.type, 'MATCH');
    expect(last.target, kDefaultGroupName);
  });

  test('迁移时补建 DEFAULT，放最前且成员覆盖全部节点 + DIRECT + REJECT', () {
    final migrated = ConfigOps.migrateDefaultGroup(_doc(_twoNodes));
    final profile = Profile.from(migrated);
    expect(profile.groups.first.name, kDefaultGroupName);
    expect(profile.group(kDefaultGroupName)!.members, [
      'a',
      'b',
      'DIRECT',
      'REJECT',
    ]);
    // 已有规则不动：迁移只解决"默认 target 没有落脚点"。
    expect(profile.rules.single.target, 'PROXY');
  });

  test('迁移是幂等的', () {
    final once = ConfigOps.migrateDefaultGroup(_doc(_twoNodes)).text;
    final twice = ConfigOps.migrateDefaultGroup(YamlDoc.parse(once)).text;
    expect(twice, once);
  });

  test('旧名「默认」会重命名为 DEFAULT，并同步改写规则目标', () {
    const legacy = '''
proxies:
  - name: a
    type: ss
    server: a.example.com
    port: 443
    cipher: aes-128-gcm
    password: x

proxy-groups:
  - name: 默认
    type: select
    proxies:
      - a

rules:
  - DOMAIN-SUFFIX,example.com,默认
  - MATCH,默认
''';
    final migrated = ConfigOps.migrateDefaultGroup(_doc(legacy));
    final profile = Profile.from(migrated);
    expect(profile.group('默认'), isNull);
    expect(profile.group(kDefaultGroupName), isNotNull);
    expect(profile.rules.first.target, kDefaultGroupName);
    expect(profile.rules.last.target, kDefaultGroupName);
    // 迁移不新增组，只改名。
    expect(profile.groups.length, 1);
  });

  test('已有 DEFAULT 时不改动配置', () {
    final doc = _doc(ProfileStore.starterConfig());
    final migrated = ConfigOps.migrateDefaultGroup(doc);
    expect(migrated.text, doc.text);
  });

  test('迁移后的规则里不存在未知 target', () {
    final profile = Profile.from(
      ConfigOps.migrateDefaultGroup(_doc(_twoNodes)),
    );
    final known = profile.allTargets;
    for (final rule in profile.rules) {
      if (rule.isTerminal) continue;
      expect(
        known,
        contains(rule.target),
        reason: '规则 ${rule.raw} 指向了不存在的 ${rule.target}',
      );
    }
  });
}
