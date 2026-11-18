import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_ui_conventions.dart';

void main() {
  group('scanSource 规则', () {
    test('Checkbox / CheckboxListTile 一律命中', () {
      final scanned = scanSource('lib/ui/example.dart', '''
Widget build(BuildContext context) {
  return Column(
    children: [
      Checkbox(value: true, onChanged: (_) {}),
      CheckboxListTile(value: false, onChanged: (_) {}),
    ],
  );
}
''');
      final rules = scanned.violations.map((v) => v.rule).toSet();
      expect(rules, contains('no-checkbox'));
      expect(scanned.violations.length, 2);
    });

    test('showDialog 与 AlertDialog 分属两条规则', () {
      final scanned = scanSource('lib/ui/example.dart', '''
Future<void> f(BuildContext context) async {
  await showDialog<void>(context: context, builder: (_) => AlertDialog(title: const Text('x')));
}
''');
      final rules = scanned.violations.map((v) => v.rule).toSet();
      expect(rules, contains('no-show-dialog'));
      expect(scanned.alertCount, 1);
    });

    test('showModalBottomSheet 允许共享封装，业务文件命中', () {
      final shared = scanSource(
        'lib/ui/sheets.dart',
        'Future<void> f() => showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox());',
      );
      expect(
        shared.violations.map((v) => v.rule),
        isNot(contains('no-raw-sheet')),
      );

      final business = scanSource(
        'lib/ui/some_page.dart',
        'Future<void> f() => showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox());',
      );
      expect(business.violations.map((v) => v.rule), contains('no-raw-sheet'));
    });

    test('showAppDialog 必须带 width', () {
      final scanned = scanSource(
        'lib/ui/example.dart',
        'Future<void> f(BuildContext context) => showAppDialog<void>(context, builder: (_) => const SizedBox());',
      );
      expect(scanned.widthlessCount, 1);
      expect(scanned.violations.map((v) => v.rule), contains('dialog-width'));

      final withWidth = scanSource(
        'lib/ui/example.dart',
        'Future<void> f(BuildContext context) => showAppDialog<void>(context, width: dialogWidthOf(context), builder: (_) => const SizedBox());',
      );
      expect(withWidth.widthlessCount, 0);
    });

    test('函数声明不算调用', () {
      final scanned = scanSource(
        'lib/ui/example.dart',
        'Future<T?> showAppDialog<T>(BuildContext context, {required WidgetBuilder builder}) async => null;',
      );
      expect(scanned.widthlessCount, 0);
      expect(scanned.violations, isEmpty);
    });
  });

  test('lib/ui 现有代码没有超出基线的违规', () {
    final violations = scanTree(
      Directory('lib/ui'),
      baseline: loadBaseline(File('tool/ui_conventions_baseline.txt')),
    );
    expect(
      violations,
      isEmpty,
      reason: violations.map((v) => v.toString()).join('\n'),
    );
  });
}
