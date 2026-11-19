import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_config.dart';
import 'package:flutter_test/flutter_test.dart';

/// DNS 不做强制：用户显式写的 `dns.enable` 一律保留，TUN 下也一样。
/// 只有完全没写 dns 段时才补默认值（enable/fake-ip-range/nameserver）。
void main() {
  const base = '''
mixed-port: 7890
mode: rule
dns:
  enable: false
  enhanced-mode: redir-host
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,PROXY
''';

  test('TUN 模式保留用户关闭的 dns.enable，并写入 fd', () {
    final out = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(base),
      tunFileDescriptor: 42,
    );
    final doc = YamlDoc.parse(out);
    expect(doc.plainAt(['dns', 'enable']), isFalse);
    expect((doc.plainAt(['tun']) as Map)['file-descriptor'], 42);
  });

  test('仅端口模式保留用户关闭的 dns.enable，并显式关掉 TUN', () {
    final out = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(base),
      tunFileDescriptor: 0,
    );
    final doc = YamlDoc.parse(out);
    expect(doc.plainAt(['dns', 'enable']), isFalse);
    expect(doc.plainAt(['tun', 'enable']), isFalse);
  });

  test('TUN 模式没有 dns 段时补默认段（enable 默认 true）', () {
    const minimal = '''
mixed-port: 7890
proxies: []
rules:
  - MATCH,DIRECT
''';
    final out = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(minimal),
      tunFileDescriptor: 7,
    );
    final doc = YamlDoc.parse(out);
    expect(doc.plainAt(['dns', 'enable']), isTrue);
    expect(doc.plainAt(['dns', 'fake-ip-range']), '198.18.0.1/16');
    expect(doc.plainAt(['tun', 'dns-hijack']), ['any:53']);
  });
}
