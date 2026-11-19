import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/speed_test.dart';
import 'package:flutter_test/flutter_test.dart';

const _selectYaml = '''
proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK-01, JP-01]
''';

const _selectorYaml = '''
proxy-groups:
  - name: LEGACY
    type: selector
    proxies: [HK-01]
''';

const _otherTypesYaml = '''
proxy-groups:
  - name: AUTO
    type: url-test
    proxies: [HK-01]
  - name: FALLBACK
    type: fallback
    proxies: [HK-01]
''';

const _noNodeYaml = '''
proxy-groups:
  - name: PROXY
    type: select
    proxies: [OTHER]
''';

void main() {
  test('type: select + proxies 能选中节点', () {
    final picked = pickSpeedTestSelector(YamlDoc.parse(_selectYaml), 'JP-01');
    expect(picked?.group, 'PROXY');
    expect(picked?.node, 'JP-01');
  });

  test('type: selector 也支持', () {
    final picked = pickSpeedTestSelector(YamlDoc.parse(_selectorYaml), 'HK-01');
    expect(picked?.group, 'LEGACY');
  });

  test('DEFAULT 优先于其它 select 组', () {
    const yaml = '''
proxy-groups:
  - name: PROXY
    type: select
    proxies: [HK-01]
  - name: DEFAULT
    type: select
    proxies: [HK-01]
''';
    final picked = pickSpeedTestSelector(YamlDoc.parse(yaml), 'HK-01');
    expect(picked?.group, 'DEFAULT');
  });

  test('组里没有该节点时返回 null', () {
    expect(pickSpeedTestSelector(YamlDoc.parse(_noNodeYaml), 'HK-01'), isNull);
  });

  test('非 select/selector 组一律跳过', () {
    expect(
      pickSpeedTestSelector(YamlDoc.parse(_otherTypesYaml), 'HK-01'),
      isNull,
    );
  });

  test('没有 proxy-groups 时返回 null', () {
    expect(
      pickSpeedTestSelector(
        YamlDoc.parse('proxies:\n  - {name: HK-01, type: ss}\n'),
        'HK-01',
      ),
      isNull,
    );
  });
}
