import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:clashdeck/ui/runtime_diagnostic_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const base = '''
mixed-port: 7890
mode: rule
dns:
  enable: false
tun:
  stack: system
  mtu: 8600
proxies:
  - {name: A, type: ss, server: 1.2.3.4, port: 8388, cipher: aes-128-gcm, password: pw}
proxy-groups:
  - name: DEFAULT
    type: select
    proxies: [A, DIRECT]
rules:
  - MATCH,DEFAULT
''';

  test('诊断文本包含模式、DNS、TUN 参数与日志占位', () {
    final runtime = RuntimeController(
      configProvider: () => YamlDoc.parse(base),
      androidOverride: true,
      pollInterval: const Duration(hours: 1),
    );
    addTearDown(runtime.dispose);

    final report = buildRuntimeDiagnostic(
      appVersion: '0.3.3',
      runtime: runtime,
      settings: null,
    );

    expect(report, contains('ClashDeck 0.3.3'));
    expect(report, contains('分流模式：rule'));
    expect(report, contains('dns.enable：false'));
    expect(report, contains('TUN stack：system'));
    expect(report, contains('TUN mtu：8600'));
    expect(report, contains('DEFAULT 当前出口：A'));
    expect(report, contains('TUN 已建立：否'));
    expect(report, contains('最后错误：—'));
    expect(report, contains('代理流量：↑0B ↓0B'));
    expect(report, contains('（暂无日志）'));
  });

  test('版本为空时显示未知版本', () {
    final runtime = RuntimeController(
      configProvider: () => YamlDoc.parse(base),
      androidOverride: true,
      pollInterval: const Duration(hours: 1),
    );
    addTearDown(runtime.dispose);

    expect(
      buildRuntimeDiagnostic(appVersion: '', runtime: runtime, settings: null),
      contains('ClashDeck （未知版本）'),
    );
  });
}
