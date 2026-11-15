import 'package:clashdeck/core/edit/import_links.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:flutter_test/flutter_test.dart';

const _vless =
    'vless://b831381d-6324-4d53-ad4f-8cda48b30811@hk.example.com:443'
    '?encryption=none&security=tls&sni=cdn.example.com&type=ws&path=%2Fws#香港 01';
const _trojan = 'trojan://pass@us.example.com:443?sni=us.example.com#美国 01';
const _hy2 = 'hysteria2://pw@tw.example.com:8443?sni=tw.example.com#台湾 01';

void main() {
  YamlDoc starter() => YamlDoc.parse(ProfileStore.starterConfig(name: 't'));

  test('单条 vless 链接导入，并加入指定组', () {
    final out = importLinks(starter(), _vless, group: 'PROXY');
    expect(out.added, ['香港 01']);
    expect(out.renamed, isEmpty);
    final profile = EditorState.fromText(out.doc.text).profile;
    expect(profile.proxyByName.containsKey('香港 01'), isTrue);
    expect(profile.groupByName['PROXY']!.members, contains('香港 01'));
    expect(out.doc.text.contains('type: vless'), isTrue);
  });

  test('多行混合链接 + 注释 + 垃圾行，一次导入只取能解析的', () {
    final text = '''
# 我的机场
$_vless
$_trojan
不是链接的一行
$_hy2
''';
    final out = importLinks(starter(), text, group: 'PROXY');
    expect(out.added, ['香港 01', '美国 01', '台湾 01']);
    final types = EditorState.fromText(out.doc.text)
        .profile
        .proxies
        .map((p) => p.type)
        .toList();
    expect(types, ['vless', 'trojan', 'hysteria2']);
  });

  test('重名自动加后缀，且不会撞上策略组名', () {
    final first = importLinks(starter(), _vless, group: 'PROXY');
    final second = importLinks(first.doc, _vless, group: 'PROXY');
    expect(second.added, ['香港 01-2']);
    expect(second.renamed, {'香港 01': '香港 01-2'});

    // 节点名与组名同名也要避开（内核要求 proxies/proxy-groups 名字全局唯一）
    final groupClash = importLinks(
      second.doc,
      'vless://b831381d-6324-4d53-ad4f-8cda48b30811@x.example.com:443?encryption=none#PROXY',
    );
    expect(groupClash.added, ['PROXY-2']);
  });

  test('解析不出任何节点时抛 ConfigEditException，且不改文档', () {
    final doc = starter();
    expect(
      () => importLinks(doc, 'hello world\n没用的一堆字'),
      throwsA(isA<ConfigEditException>()),
    );
    expect(doc.text, starter().text);
  });

  test('skipExisting 时按名字跳过已有节点（订阅刷新用）', () {
    final first = importLinks(starter(), _vless);
    final again = importProxies(
      first.doc,
      [
        {'name': '香港 01', 'type': 'vless', 'server': 'new.example.com', 'port': 443, 'uuid': 'u'},
        {'name': '新节点', 'type': 'ss', 'server': 'n.example.com', 'port': 8388, 'cipher': 'aes-128-gcm', 'password': 'p'},
      ],
      skipExisting: true,
    );
    expect(again.added, ['新节点']);
    expect(again.skipped, ['香港 01']);
    final profile = EditorState.fromText(again.doc.text).profile;
    expect(profile.proxyByName['香港 01']!.server, 'hk.example.com');
  });

  test('删除节点时组成员自动同步（这是用户明确要的行为）', () {
    final out = importLinks(starter(), _vless, group: 'PROXY');
    final state = EditorState.fromText(out.doc.text);
    expect(state.profile.groupByName['PROXY']!.members, contains('香港 01'));
    expect(state.deleteProxy('香港 01'), isTrue);
    expect(state.profile.proxyNames, isEmpty);
    expect(
      state.profile.groupByName['PROXY']!.members,
      isNot(contains('香港 01')),
    );
  });
}
