import 'package:clashdeck/core/edit/member_order.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const proxyOrder = ['HK-01', 'JP-01'];

  group('normalizeMemberOrder', () {
    test('节点 → 其它成员 → DIRECT → REJECT，节点按 proxies 顺序', () {
      expect(
        normalizeMemberOrder([
          'REJECT',
          'AUTO',
          'HK-01',
          'DIRECT',
          'JP-01',
          'PROXY',
        ], proxyOrder: proxyOrder),
        ['HK-01', 'JP-01', 'AUTO', 'PROXY', 'DIRECT', 'REJECT'],
      );
    });

    test('节点按 proxies 声明顺序排列，不按成员里的先后', () {
      expect(
        normalizeMemberOrder([
          'JP-01',
          'HK-01',
          'DIRECT',
        ], proxyOrder: proxyOrder),
        ['HK-01', 'JP-01', 'DIRECT'],
      );
    });

    test('其它成员保持原有相对顺序', () {
      expect(
        normalizeMemberOrder([
          'REJECT',
          'PROXY',
          'AUTO',
          'DIRECT',
        ], proxyOrder: proxyOrder),
        ['PROXY', 'AUTO', 'DIRECT', 'REJECT'],
      );
    });

    test('其它内置排在 DIRECT / REJECT 之后，相对顺序不变', () {
      expect(
        normalizeMemberOrder([
          'GLOBAL',
          'DIRECT',
          'PASS',
          'REJECT-DROP',
          'REJECT',
          'COMPATIBLE',
        ], proxyOrder: proxyOrder),
        ['DIRECT', 'REJECT', 'GLOBAL', 'PASS', 'REJECT-DROP', 'COMPATIBLE'],
      );
    });

    test('空列表与全内置列表', () {
      expect(normalizeMemberOrder(const [], proxyOrder: proxyOrder), isEmpty);
      expect(
        normalizeMemberOrder(['REJECT', 'DIRECT'], proxyOrder: proxyOrder),
        ['DIRECT', 'REJECT'],
      );
    });
  });

  group('defaultGroupSelection', () {
    test('记住的成员仍存在时优先', () {
      expect(
        defaultGroupSelection(
          ['HK-01', 'JP-01'],
          proxyOrder: proxyOrder,
          saved: 'JP-01',
        ),
        'JP-01',
      );
    });

    test('记住的成员已不存在时回落到节点', () {
      expect(
        defaultGroupSelection(
          ['JP-01', 'HK-01'],
          proxyOrder: proxyOrder,
          saved: '已删除',
        ),
        'HK-01',
      );
    });

    test('节点优先于 DIRECT（顺序无关）', () {
      expect(
        defaultGroupSelection(['DIRECT', 'HK-01'], proxyOrder: proxyOrder),
        'HK-01',
      );
    });

    test('没有节点时依次回落策略组 → DIRECT → REJECT', () {
      expect(
        defaultGroupSelection(['AUTO', 'DIRECT'], proxyOrder: proxyOrder),
        'AUTO',
      );
      expect(
        defaultGroupSelection(['REJECT', 'DIRECT'], proxyOrder: proxyOrder),
        'DIRECT',
      );
      expect(
        defaultGroupSelection(['REJECT'], proxyOrder: proxyOrder),
        'REJECT',
      );
    });

    test('空组返回 null', () {
      expect(defaultGroupSelection(const [], proxyOrder: proxyOrder), isNull);
    });
  });
}
