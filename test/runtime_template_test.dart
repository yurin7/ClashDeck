import 'package:clashdeck/runtime/runtime_template.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const yaml = '''
mixed-port: 7890
tun:
  enable: true
  stack: gvisor
  file-descriptor: 42
  dns-hijack:
    - any:53
dns:
  enable: true
''';

  test('模板把实际 fd 换成 0，其余原样保留', () {
    final tpl = runtimeTemplateFrom(yaml);
    expect(tpl.contains('file-descriptor: 0'), isTrue);
    expect(tpl.contains('file-descriptor: 42'), isFalse);
    expect(tpl.contains('stack: gvisor'), isTrue);
    expect(tpl.contains('dns-hijack'), isTrue);
  });

  test('用真实 fd 回填模板，得到与最初一致的内容', () {
    final round = runtimeYamlFromTemplate(runtimeTemplateFrom(yaml), 42);
    expect(round, yaml);
  });

  test('仅端口模式的 fd=0 也视为合法占位', () {
    final tpl = runtimeTemplateFrom(yaml.replaceFirst('42', '0'));
    expect(tpl.contains('file-descriptor: 0'), isTrue);
    expect(runtimeYamlFromTemplate(tpl, 0), contains('file-descriptor: 0'));
  });

  test('没有 file-descriptor 行时模板检测为 false', () {
    const plain = 'mixed-port: 7890\ntun:\n  enable: false\n';
    expect(runtimeTemplateHasPlaceholder(plain), isFalse);
    expect(runtimeYamlFromTemplate(plain, 3), plain);
  });
}
