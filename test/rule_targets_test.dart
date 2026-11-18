import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/edit/rule_targets.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _yaml = r'''mixed-port: 7890
mode: rule
proxy-groups:
  - name: 自定义A
    type: select
    proxies:
      - DIRECT
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
      - REJECT
  - name: 自动选择
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - DIRECT
  - name: 自定义B
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,DEFAULT
''';

Profile _profile(String text) {
  final doc = YamlDoc.parse(text);
  expect(doc.isValid, isTrue, reason: '${doc.error}');
  return Profile.from(doc);
}

void main() {
  test('主列表顺序：自定义组 → DEFAULT → 自动选择 → DIRECT → REJECT', () {
    final targets = ruleTargetsFor(_profile(_yaml));
    expect(targets.primary, [
      '自定义A',
      '自定义B',
      kDefaultGroupName,
      kAutoGroupName,
      'DIRECT',
      'REJECT',
    ]);
    expect(targets.otherBuiltins, [
      'REJECT-DROP',
      'PASS',
      'COMPATIBLE',
      'GLOBAL',
    ]);
  });

  test('当前值不在列表里也要能显示（且不重复）', () {
    final targets = ruleTargetsFor(_profile(_yaml), preferred: '已删除的组');
    expect(targets.primary.last, '已删除的组');

    final again = ruleTargetsFor(_profile(_yaml), preferred: '自定义A');
    expect(again.primary.where((e) => e == '自定义A').length, 1);
  });

  test('冷门内置当前值进主列表，并从其它内置里去掉', () {
    final targets = ruleTargetsFor(_profile(_yaml), preferred: 'PASS');
    expect(targets.primary.last, 'PASS');
    expect(targets.otherBuiltins, isNot(contains('PASS')));
    expect(targets.all.toSet().length, targets.all.length);
  });

  test('没有 DEFAULT / 自动选择时只补系统策略', () {
    final targets = ruleTargetsFor(
      _profile('''mixed-port: 7890
proxy-groups:
  - name: ONLY
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,ONLY
'''),
    );
    expect(targets.primary, ['ONLY', 'DIRECT', 'REJECT']);
  });
}
