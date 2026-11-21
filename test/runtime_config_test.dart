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

  test('Windows TUN 由内核建网卡，禁用时即使 YAML 含 TUN 也只监听端口', () {
    final source = YamlDoc.parse('''
$base
tun:
  enable: true
  file-descriptor: 42
  mtu: 1500
''');
    final tun = YamlDoc.parse(
      RuntimeConfig.buildRuntimeYaml(
        source,
        tunFileDescriptor: 0,
        windows: true,
        windowsTunStack: RuntimeConfig.defaultWindowsStack,
      ),
    );
    expect(tun.plainAt(['tun', 'enable']), isTrue);
    expect(tun.plainAt(['tun', 'stack']), 'mixed');
    expect(tun.plainAt(['tun', 'auto-route']), isTrue);
    expect(tun.plainAt(['tun', 'auto-detect-interface']), isTrue);
    expect(tun.plainAt(['tun', 'mtu']), 1500);
    expect(tun.has(['tun', 'file-descriptor']), isFalse);
    expect(tun.plainAt(['dns', 'enable']), isFalse);
    expect(tun.plainAt(['find-process-mode']), 'always');

    final local = YamlDoc.parse(
      RuntimeConfig.buildRuntimeYaml(
        source,
        tunFileDescriptor: 0,
        windows: true,
      ),
    );
    expect(local.plainAt(['tun', 'enable']), isFalse);
    expect(source.plainAt(['tun', 'enable']), isTrue);
  });
}
