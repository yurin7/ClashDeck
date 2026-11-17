import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/edit/import_plan.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('isValidGeositeCode', () {
    test('接受自由输入的小写 code', () {
      expect(isValidGeositeCode('openai'), isTrue);
      expect(isValidGeositeCode('category-ai'), isTrue);
      expect(isValidGeositeCode(' openai '), isTrue);
      expect(isValidGeositeCode('bilibili2'), isTrue);
    });

    test('拒绝大写、空格和逗号', () {
      expect(isValidGeositeCode('AI'), isFalse);
      expect(isValidGeositeCode('bad code'), isFalse);
      expect(isValidGeositeCode('a,b'), isFalse);
      expect(isValidGeositeCode(''), isFalse);
    });
  });

  group('planGeositeRules', () {
    test('合法 code 生成 GEOSITE 行，目标默认 DEFAULT', () {
      final plan = planGeositeRules(codes: ['openai']);
      expect(plan.rules, ['GEOSITE,openai,DEFAULT']);
      expect(plan.isEmpty, isFalse);
      expect(plan.invalid, isEmpty);
      expect(plan.skipped, isEmpty);
      expect(kDefaultGroupName, 'DEFAULT');
    });

    test('批量：顺序稳定、重复去重、已存在跳过', () {
      final plan = planGeositeRules(
        codes: ['openai', 'netflix', 'openai', 'steam'],
        existingCodes: ['netflix'],
      );
      expect(plan.rules, ['GEOSITE,openai,DEFAULT', 'GEOSITE,steam,DEFAULT']);
      expect(plan.skipped, ['netflix']);
      expect(plan.invalid, isEmpty);
    });

    test('非法字符进 invalid，不写进 rules', () {
      final plan = planGeositeRules(codes: ['bad code', 'a,b', 'openai']);
      expect(plan.rules, ['GEOSITE,openai,DEFAULT']);
      expect(plan.invalid, ['bad code', 'a,b']);
      expect(plan.isEmpty, isFalse);
    });

    test('精选里带感叹号的分类名可以写', () {
      final plan = planGeositeRules(codes: ['category-ai-!cn']);
      expect(plan.rules, ['GEOSITE,category-ai-!cn,DEFAULT']);
      expect(plan.invalid, isEmpty);
    });

    test('输入做小写归一化', () {
      final plan = planGeositeRules(codes: [' OpenAI ']);
      expect(plan.rules, ['GEOSITE,openai,DEFAULT']);
    });

    test('可以指定目标组', () {
      final plan = planGeositeRules(codes: ['openai'], target: 'PROXY');
      expect(plan.rules, ['GEOSITE,openai,PROXY']);
    });

    test('只选了已存在的 code 时计划为空', () {
      final plan = planGeositeRules(
        codes: ['openai'],
        existingCodes: ['openai'],
      );
      expect(plan.rules, isEmpty);
      expect(plan.isEmpty, isTrue);
      expect(plan.skipped, ['openai']);
    });
  });
}
