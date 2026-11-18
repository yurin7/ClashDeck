import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../tool/check_ui_conventions.dart';

/// `lib/ui` 的共享封装是 **0 基线**：不是「历史欠账只减不增」，而是一处都不许有。
///
/// 这些模式一旦重新出现，说明有人绕过了共享组件；自检脚本会在 CI 里失败，
/// 这个测试让本地 `flutter test` 也立刻红。
void main() {
  test('lib/ui 不允许任何绕过共享封装的写法（0 基线）', () {
    final violations = scanTree(Directory('lib/ui'));
    expect(
      violations,
      isEmpty,
      reason:
          '发现 ${violations.length} 处违规：\n'
          '${violations.map((v) => '  $v').join('\n')}\n'
          '共享封装见 lib/ui/widgets/app_ink.dart、lib/ui/fields.dart、'
          'lib/ui/widgets/edit_dialog.dart、lib/ui/navigation.dart。',
    );
  });

  test('每个禁用模式在业务代码里都是 0 处', () {
    final files = Directory('lib/ui')
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.endsWith('.dart'))
        .toList();
    expect(files, isNotEmpty);
    final counts = <String, int>{};
    for (final file in files) {
      final relative = file.path.replaceAll('\\', '/');
      final source = stripLineComment(file.readAsStringSync());
      for (final entry in bannedPatterns) {
        if (entry.allow.contains(relative)) continue;
        final regex = RegExp(
          '(?<![A-Za-z0-9_\$])${RegExp.escape(entry.pattern)}',
        );
        final count = regex.allMatches(source).length;
        if (count > 0) {
          counts['$relative ${entry.pattern}'] = count;
        }
      }
    }
    expect(counts, isEmpty, reason: '仍在使用裸组件：$counts');
  });
}
