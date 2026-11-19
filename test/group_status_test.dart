import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/edit/group_status.dart';
import 'package:clashdeck/core/model/profile.dart';

void main() {
  GroupEntry group(String type, List<String> members) => GroupEntry(
    index: 0,
    name: 'G',
    type: type,
    members: members,
    raw: {'name': 'G', 'type': type, 'proxies': members},
  );

  test('select：只显示运行时选中的成员', () {
    expect(
      groupCurrentLabel(
        group: group('select', ['a', 'b']),
        delays: {'a': 300, 'b': 120},
        selectedName: 'a',
      ),
      '当前 a',
    );
    expect(
      groupCurrentLabel(
        group: group('select', ['a']),
        delays: const {},
        selectedName: null,
      ),
      isNull,
    );
    // 运行时选中的名字不在成员里时不显示。
    expect(
      groupCurrentLabel(
        group: group('select', ['a']),
        delays: const {},
        selectedName: 'z',
      ),
      isNull,
    );
  });

  test('url-test：取已测延迟最低的成员', () {
    expect(
      groupCurrentLabel(
        group: group('url-test', ['a', 'b', 'c']),
        delays: {'a': 300, 'b': 120, 'c': null},
        selectedName: 'a',
      ),
      '当前 b · 最低延迟',
    );
  });

  test('fallback：没延迟数据时退回运行时选中值', () {
    expect(
      groupCurrentLabel(
        group: group('fallback', ['a', 'b']),
        delays: const {},
        selectedName: 'b',
      ),
      '当前 b',
    );
    expect(
      groupCurrentLabel(
        group: group('fallback', ['a', 'b']),
        delays: {'a': 88},
        selectedName: 'b',
      ),
      '当前 a',
    );
  });

  test('load-balance：显示节点数而不是单一出口', () {
    expect(
      groupCurrentLabel(
        group: group('load-balance', ['a', 'b', 'c']),
        delays: const {},
        selectedName: 'a',
      ),
      '自动均衡 · 3 节点',
    );
  });

  test('relay 与空成员组', () {
    expect(
      groupCurrentLabel(
        group: group('relay', ['a', 'b']),
        delays: const {},
        selectedName: 'a',
      ),
      '当前 a',
    );
    expect(
      groupCurrentLabel(
        group: group('load-balance', const []),
        delays: const {},
        selectedName: null,
      ),
      isNull,
    );
  });
}
