import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_ui_conventions.dart';

void main() {
  group('禁用裸组件', () {
    test('Checkbox / CheckboxListTile 及其 adaptive 变体都命中', () {
      final violations = scanSource('lib/ui/example.dart', '''
Widget build(BuildContext context) {
  return Column(
    children: [
      Checkbox(value: true, onChanged: (_) {}),
      Checkbox.adaptive(value: true, onChanged: (_) {}),
      CheckboxListTile(value: false, onChanged: (_) {}),
      CheckboxListTile.adaptive(value: false, onChanged: (_) {}),
    ],
  );
}
''');
      expect(violations.where((v) => v.rule == 'no-checkbox'), hasLength(4));
    });

    test('共享封装的调用不会被负向回顾误伤', () {
      final violations = scanSource('lib/ui/example.dart', '''
Widget build(BuildContext context) {
  return Column(
    children: [
      AppTextField(label: 'a'),
      AppInkWell(onTap: () {}),
      AppDropdown<String>(label: 'b', options: const []),
    ],
  );
}
''');
      expect(violations, isEmpty);
    });

    test('AlertDialog 在业务文件命中，在共享封装里放行', () {
      final source = '''
Widget build(BuildContext context) {
  return AlertDialog(title: const Text('x'));
}
''';
      expect(
        scanSource(
          'lib/ui/example.dart',
          source,
        ).where((v) => v.rule == 'no-raw-alert'),
        hasLength(1),
      );
      expect(scanSource('lib/ui/widgets/edit_dialog.dart', source), isEmpty);
    });

    test('SimpleDialog / SimpleDialogOption / 裸 Dialog 都命中', () {
      final violations = scanSource('lib/ui/example.dart', '''
Widget build(BuildContext context) {
  return SimpleDialog(
    children: [SimpleDialogOption(onPressed: () {}, child: const Text('x'))],
  );
}
''');
      expect(
        violations.where((v) => v.rule == 'no-raw-simpledialog'),
        hasLength(2),
      );
      expect(
        scanSource(
          'lib/ui/example.dart',
          'Widget x() => Dialog(child: c);',
        ).where((v) => v.rule == 'no-raw-dialog'),
        hasLength(1),
      );
    });

    test('MaterialPageRoute / DropdownButton / InkResponse 都命中', () {
      final violations = scanSource('lib/ui/example.dart', '''
Route<void> route(Widget page) => MaterialPageRoute<void>(builder: (_) => page);
Widget menu() => DropdownButton<String>(items: const []);
Widget row() => InkResponse(onTap: () {});
''');
      expect(
        violations.map((v) => v.rule),
        containsAll(<String>[
          'no-raw-route',
          'no-raw-dropdown',
          'no-raw-inkresponse',
        ]),
      );
    });

    test('仅出现在注释里的调用不算', () {
      final violations = scanSource('lib/ui/example.dart', '''
// 旧写法：AlertDialog(title: ...)
Widget build(BuildContext context) => const SizedBox();
''');
      expect(violations, isEmpty);
    });
  });

  group('弹窗与导航约定', () {
    test('showAppDialog 必须带 width', () {
      final missing = scanSource('lib/ui/example.dart', '''
Future<void> open(BuildContext context) {
  return showAppDialog<void>(context, builder: (_) => const SizedBox());
}
''');
      expect(missing.where((v) => v.rule == 'dialog-width'), hasLength(1));

      final ok = scanSource('lib/ui/example.dart', '''
Future<void> open(BuildContext context) {
  return showAppDialog<void>(
    context,
    width: dialogWidthOf(context),
    builder: (_) => const SizedBox(),
  );
}
''');
      expect(ok.where((v) => v.rule == 'dialog-width'), isEmpty);
    });

    test('showDialog 一律禁止', () {
      final violations = scanSource('lib/ui/example.dart', '''
Future<void> open(BuildContext context) {
  return showDialog<void>(context: context, builder: (_) => const SizedBox());
}
''');
      expect(violations.where((v) => v.rule == 'no-show-dialog'), hasLength(1));
    });

    test('showModalBottomSheet 只允许 sheets.dart', () {
      final source = '''
Future<void> open(BuildContext context) {
  return showModalBottomSheet<void>(context: context, builder: (_) => const SizedBox());
}
''';
      expect(
        scanSource(
          'lib/ui/example.dart',
          source,
        ).where((v) => v.rule == 'no-raw-sheet'),
        hasLength(1),
      );
      expect(
        scanSource(
          'lib/ui/sheets.dart',
          source,
        ).where((v) => v.rule == 'no-raw-sheet'),
        isEmpty,
      );
    });

    test('目标组不得用 AppDropdown(label: 目标…)', () {
      final violations = scanSource('lib/ui/example.dart', '''
Widget build(BuildContext context) {
  return AppDropdown<String>(label: '目标', options: const []);
}
''');
      expect(
        violations.where((v) => v.rule == 'no-dropdown-target'),
        hasLength(1),
      );
    });
  });

  test('lib/ui 当前 0 违规', () {
    expect(scanTree(Directory('lib/ui')), isEmpty);
  });
}
