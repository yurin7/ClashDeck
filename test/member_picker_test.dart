import 'package:clashdeck/core/edit/member_picker.dart';
import 'package:flutter_test/flutter_test.dart';

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
}
