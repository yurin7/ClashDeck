import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_config.dart';
import 'package:clashdeck/runtime/runtime_template.dart';
import 'package:flutter_test/flutter_test.dart';

/// mihomo 1.10 移除了 `type: relay`：运行配置里必须展开成 dialer-proxy 链。
/// 用户存的 YAML 不动，只有派生出来的运行配置带隐藏代理。
void main() {
  const threeMembers = '''
mixed-port: 7890
mode: rule
proxies:
  - {name: A, type: ss, server: a.example, port: 443, cipher: aes-128-gcm, password: p}
  - {name: B, type: ss, server: b.example, port: 443, cipher: aes-128-gcm, password: p}
  - {name: C, type: ss, server: c.example, port: 443, cipher: aes-128-gcm, password: p}
proxy-groups:
  - name: 链式
    type: relay
    proxies: [A, B, C]
  - name: PROXY
    type: select
    proxies: [链式, DIRECT]
rules:
  - MATCH,PROXY
''';

  test('relay 组展开成 dialer-proxy 链，原组名改成只放末级的 select', () {
    final out = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(threeMembers),
      tunFileDescriptor: 0,
    );
    final doc = YamlDoc.parse(out);
    final proxies = (doc.plainAt(['proxies']) as List).cast<Map>();
    final byName = <String, Map>{
      for (final proxy in proxies) '${proxy['name']}': proxy,
    };
    expect(
      byName.keys,
      containsAll(['__chain_链式_1', '__chain_链式_2', '__chain_链式_3']),
    );
    expect(byName['__chain_链式_1']!.containsKey('dialer-proxy'), isFalse);
    expect(byName['__chain_链式_2']!['dialer-proxy'], '__chain_链式_1');
    expect(byName['__chain_链式_3']!['dialer-proxy'], '__chain_链式_2');
    // 协议字段整段复制，只换 name。
    expect(byName['__chain_链式_2']!['server'], 'b.example');
    expect(byName['__chain_链式_2']!['cipher'], 'aes-128-gcm');

    final groups = (doc.plainAt(['proxy-groups']) as List).cast<Map>();
    final chain = groups.firstWhere((group) => group['name'] == '链式');
    expect(chain['type'], 'select');
    expect(chain['proxies'], ['__chain_链式_3']);
    expect('${chain['type']}', isNot('relay'));
  });

  test('单节点 relay 收敛成 select，不生成隐藏代理', () {
    const single = '''
mixed-port: 7890
proxies:
  - {name: A, type: ss, server: a.example, port: 443, cipher: aes-128-gcm, password: p}
proxy-groups:
  - name: 链式
    type: relay
    proxies: [A]
rules:
  - MATCH,链式
''';
    final out = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(single),
      tunFileDescriptor: 0,
    );
    final doc = YamlDoc.parse(out);
    final groups = (doc.plainAt(['proxy-groups']) as List).cast<Map>();
    expect(groups.single['type'], 'select');
    expect(groups.single['proxies'], ['A']);
    expect(out.contains('__chain_'), isFalse);
  });

  test('空 relay 组收敛成 DIRECT，不产生隐藏代理', () {
    const empty = '''
mixed-port: 7890
proxies: []
proxy-groups:
  - name: 链式
    type: relay
    proxies: []
rules:
  - MATCH,DIRECT
''';
    final out = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(empty),
      tunFileDescriptor: 0,
    );
    final doc = YamlDoc.parse(out);
    final groups = (doc.plainAt(['proxy-groups']) as List).cast<Map>();
    expect(groups.single['type'], 'select');
    expect(groups.single['proxies'], ['DIRECT']);
    expect(out.contains('__chain_'), isFalse);
  });

  test('冷启动模板继承展开结果，且保留 file-descriptor 占位', () {
    final out = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(threeMembers),
      tunFileDescriptor: 42,
    );
    final template = runtimeTemplateFrom(out);
    expect(template, contains('__chain_链式_1'));
    expect(runtimeTemplateHasPlaceholder(template), isTrue);

    final withFd = YamlDoc.parse(runtimeYamlFromTemplate(template, 123));
    expect(withFd.plainAt(['tun', 'file-descriptor']), 123);
  });
}
