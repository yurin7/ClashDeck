import 'package:clashdeck/core/edit/member_picker.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _profileYaml = r'''mixed-port: 7890
proxies:
  - name: n1
    type: vless
    server: a.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
  - name: n2
    type: vless
    server: b.example.com
    port: 443
    uuid: 66666666-7777-8888-9999-000000000000
proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
      - REJECT
  - name: OTHER
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,DEFAULT
''';

void main() {
  const all = <MemberCandidate>[
    MemberCandidate(name: '香港 01 WS'),
    MemberCandidate(name: '日本 REALITY'),
    MemberCandidate(name: '美国 gRPC', inGroup: true),
    MemberCandidate(name: 'Netflix', isGroup: true),
    MemberCandidate(name: '媒体', isGroup: true, inGroup: true),
  ];

  group('filterMemberCandidates', () {
    test('关键字命中名字子串', () {
      final hit = filterMemberCandidates(all, '日本');
      expect(hit.map((c) => c.name), ['日本 REALITY']);

      final ascii = filterMemberCandidates(all, 'gRPC');
      expect(ascii.map((c) => c.name), ['美国 gRPC']);
    });

    test('忽略大小写', () {
      final lower = filterMemberCandidates(all, 'netflix');
      final upper = filterMemberCandidates(all, 'NETFLIX');
      expect(lower.map((c) => c.name), ['Netflix']);
      expect(upper.map((c) => c.name), ['Netflix']);
    });

    test('空关键字返回全部（含已在组内的行）', () {
      expect(filterMemberCandidates(all, '   ').length, all.length);
    });

    test('过滤后仍保留已在组内的标记', () {
      final hit = filterMemberCandidates(all, '媒体');
      expect(hit.single.inGroup, isTrue);
    });
  });

  group('selectVisible', () {
    test('只选当前筛选结果里未加入的成员', () {
      final picked = selectVisible(all, 'R', <String>{});
      // 匹配 '日本 REALITY' 与 '美国 gRPC'；后者已在组内，跳过。
      expect(picked, {'日本 REALITY'});
    });

    test('已在组内的成员不会被加进来', () {
      final picked = selectVisible(all, '', <String>{});
      expect(picked.contains('美国 gRPC'), isFalse);
      expect(picked.contains('媒体'), isFalse);
      expect(picked.length, 3);
    });

    test('保留之前已经勾选的其它成员', () {
      final picked = selectVisible(all, '日本', {'香港 01 WS'});
      expect(picked, {'香港 01 WS', '日本 REALITY'});
    });
  });

  group('invertVisible', () {
    test('只翻转当前筛选结果', () {
      final picked = invertVisible(all, '日本', {'香港 01 WS'});
      expect(picked, {'香港 01 WS', '日本 REALITY'});

      final back = invertVisible(all, '日本', picked);
      expect(back, {'香港 01 WS'});
    });

    test('跳过已在组内的成员', () {
      final picked = invertVisible(all, '美国', <String>{});
      expect(picked, isEmpty);
    });
  });

  test('prunePicked 去掉已不可加入的名字', () {
    final pruned = prunePicked(all, {'日本 REALITY', '美国 gRPC', '不存在'});
    expect(pruned, {'日本 REALITY'});
  });

  group('memberCandidates', () {
    Profile profile() {
      final doc = YamlDoc.parse(_profileYaml);
      expect(doc.isValid, isTrue, reason: '${doc.error}');
      return Profile.from(doc);
    }

    test('节点之后是系统策略，再是其它策略组', () {
      final candidates = memberCandidates(
        profile(),
        groupName: 'OTHER',
        members: ['n1', 'DIRECT'],
      );
      expect(candidates.map((c) => c.name), [
        'n1',
        'n2',
        'DIRECT',
        'REJECT',
        'REJECT-DROP',
        'DEFAULT',
      ]);
      expect(candidates.first.inGroup, isTrue);
      expect(
        candidates.firstWhere((c) => c.name == 'DIRECT').isBuiltin,
        isTrue,
      );
      expect(candidates.firstWhere((c) => c.name == 'REJECT').inGroup, isFalse);
      expect(candidates.last.isGroup, isTrue);
      // 自己不出现在候选里。
      expect(candidates.any((c) => c.name == 'OTHER'), isFalse);
    });

    test('已在组内的内置出站置灰，REJECT-DROP 标「不常用」', () {
      final candidates = memberCandidates(
        profile(),
        groupName: 'DEFAULT',
        members: ['DIRECT', 'REJECT'],
      );
      final builtins = {
        for (final c in candidates.where((c) => c.isBuiltin)) c.name: c,
      };
      expect(builtins['DIRECT']!.inGroup, isTrue);
      expect(builtins['REJECT']!.inGroup, isTrue);
      expect(builtins['REJECT-DROP']!.inGroup, isFalse);
      expect(builtins['REJECT-DROP']!.note, '不常用');
    });
  });
}
