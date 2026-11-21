/// UI 约定自检：扫码 `lib/ui`，拦「绕过共享封装」的写法。
///
/// 以下规则全部为 **0 基线**：
/// 1. `AlertDialog(` → `EditDialog` / `ConfirmDialog` / `NoticeDialog`；
/// 2. `InkWell(` / `InkResponse(` → `AppInkWell`；
/// 3. `MaterialPageRoute(` → `appRoute`；
/// 4. `DropdownButton(` → `AppDropdown`；
/// 5. 裸 `TextField(` → `AppTextField` / `AppSearchField`；
/// 6. `Checkbox(` / `CheckboxListTile(` → `SelectableTile`；
/// 6b. `SimpleDialog(` / `SimpleDialogOption(` → `showSelectSheet`；
/// 6c. 裸 `Dialog(` → `showAppDialog` + 共享弹窗封装；
/// 7. 只允许 `lib/ui/sheets.dart` 直接调 `showModalBottomSheet(`；
/// 8. 禁止 `showDialog<`；
/// 9. `showAppDialog(` 必须带 `width:`；
/// 10. 目标组输入不得用 `AppDropdown(label: '目标…')`，统一 `TargetSelectorField`；
/// 11. `Dismissible(` → `SlidableRow`；
/// 12. 裸 `maxLines: null` → `AppTextArea` / `AppTextField(expands: true)`；
/// 13. `duration: const Duration(…)` → `Motion` token（`lib/ui/motion.dart`）；
/// 14. `PickerSheetScaffold(` 只允许在 `lib/ui/sheets/` 的共享面板里。
///
/// allowlist 只放共享封装文件，业务文件不得加入。
///
/// CI：`.github/workflows/release.yml` 在 Analyze 之后、Test 之前跑
///   dart run tool/check_ui_conventions.dart --check
/// 失败即 fail 整个 job。
///
/// 用法：
///   dart run tool/check_ui_conventions.dart --check
library;

import 'dart:io';

/// 一条违规。
class Violation implements Comparable<Violation> {
  const Violation(this.path, this.line, this.rule, this.message);

  final String path;
  final int line;
  final String rule;
  final String message;

  @override
  String toString() => '$path:$line [$rule] $message';

  @override
  int compareTo(Violation other) {
    final byPath = path.compareTo(other.path);
    return byPath != 0 ? byPath : line.compareTo(other.line);
  }
}

/// 裸组件禁用表：`pattern` 不能出现在 `allow` 以外的文件里。
const List<({String pattern, String rule, String message, Set<String> allow})>
bannedPatterns =
    <({String pattern, String rule, String message, Set<String> allow})>[
      (
        pattern: 'AlertDialog(',
        rule: 'no-raw-alert',
        message: 'AlertDialog 只放在共享封装里（EditDialog/ConfirmDialog/NoticeDialog）',
        allow: <String>{'lib/ui/widgets/edit_dialog.dart'},
      ),
      (
        pattern: 'InkWell(',
        rule: 'no-raw-inkwell',
        message: '点击行统一用 AppInkWell（lib/ui/widgets/app_ink.dart）',
        allow: <String>{'lib/ui/widgets/app_ink.dart'},
      ),
      (
        pattern: 'InkResponse(',
        rule: 'no-raw-inkresponse',
        message: '点击行统一用 AppInkWell（lib/ui/widgets/app_ink.dart）',
        allow: <String>{'lib/ui/widgets/app_ink.dart'},
      ),
      (
        pattern: 'MaterialPageRoute(',
        rule: 'no-raw-route',
        message: '页面跳转统一用 appRoute（lib/ui/navigation.dart）',
        allow: <String>{'lib/ui/navigation.dart'},
      ),
      (
        pattern: 'MaterialPageRoute<',
        rule: 'no-raw-route',
        message: '页面跳转统一用 appRoute（lib/ui/navigation.dart）',
        allow: <String>{'lib/ui/navigation.dart'},
      ),
      (
        pattern: 'DropdownButton(',
        rule: 'no-raw-dropdown',
        message: '下拉统一用 AppDropdown（lib/ui/dropdown.dart）',
        allow: <String>{'lib/ui/dropdown.dart'},
      ),
      (
        pattern: 'DropdownButton<',
        rule: 'no-raw-dropdown',
        message: '下拉统一用 AppDropdown（lib/ui/dropdown.dart）',
        allow: <String>{'lib/ui/dropdown.dart'},
      ),
      (
        pattern: 'SimpleDialog(',
        rule: 'no-raw-simpledialog',
        message: '选择类弹窗统一走 showSelectSheet',
        allow: <String>{},
      ),
      (
        pattern: 'SimpleDialogOption(',
        rule: 'no-raw-simpledialog',
        message: '选择类弹窗统一走 showSelectSheet',
        allow: <String>{},
      ),
      (
        pattern: 'Dialog(',
        rule: 'no-raw-dialog',
        message:
            '弹窗统一走 showAppDialog + 共享封装（EditDialog/ConfirmDialog/BusyDialog）',
        allow: <String>{'lib/ui/widgets/busy_dialog.dart'},
      ),
      (
        pattern: 'TextField(',
        rule: 'no-raw-textfield',
        message: '输入框统一用 AppTextField / AppSearchField',
        allow: <String>{'lib/ui/fields.dart'},
      ),
      (
        pattern: 'Checkbox(',
        rule: 'no-checkbox',
        message: '多选改用 SelectableTile',
        allow: <String>{},
      ),
      (
        pattern: 'Checkbox.adaptive(',
        rule: 'no-checkbox',
        message: '多选改用 SelectableTile',
        allow: <String>{},
      ),
      (
        pattern: 'CheckboxListTile(',
        rule: 'no-checkbox',
        message: '多选改用 SelectableTile',
        allow: <String>{},
      ),
      (
        pattern: 'CheckboxListTile.adaptive(',
        rule: 'no-checkbox',
        message: '多选改用 SelectableTile',
        allow: <String>{},
      ),
      (
        pattern: 'Dismissible(',
        rule: 'no-dismissible',
        message: '左滑统一用 SlidableRow（lib/ui/widgets.dart）',
        allow: <String>{},
      ),
      (
        pattern: 'maxLines: null',
        rule: 'no-raw-multiline',
        message: '多行文本统一用 AppTextArea / AppTextField(expands: true)',
        allow: <String>{'lib/ui/fields.dart'},
      ),
      (
        pattern: 'duration: const Duration(',
        rule: 'no-inline-duration',
        message: '动画时长统一用 Motion token（lib/ui/motion.dart）',
        allow: <String>{'lib/ui/motion.dart'},
      ),
      (
        pattern: 'onHorizontalDragUpdate:',
        rule: 'no-raw-swipe',
        message: '左滑手势统一用 SlidableRow，不在行内自建 onHorizontalDragUpdate',
        allow: <String>{
          'lib/ui/widgets.dart',
          'lib/ui/widgets/horizontal_drag.dart',
          'lib/ui/overview_page.dart',
        },
      ),
      (
        pattern: 'PickerSheetScaffold(',
        rule: 'no-raw-picker-scaffold',
        message:
            '业务面板走 showSectionedPicker / showSelectSheet，'
            '不在页面里直接拼 PickerSheetScaffold',
        allow: <String>{
          'lib/ui/sheets/picker_sheet.dart',
          'lib/ui/sheets/sectioned_picker.dart',
          'lib/ui/rule_picker_sheet.dart',
          'lib/ui/sheets/node_picker_sheet.dart',
        },
      ),
    ];

/// `showModalBottomSheet(` 允许出现的共享封装文件。
const Set<String> sheetAllowlist = <String>{'lib/ui/sheets.dart'};

/// 去掉行尾注释，避免注释里的示例触发误报。
String stripLineComment(String source) {
  final buffer = StringBuffer();
  for (final line in source.split('\n')) {
    final index = line.indexOf('//');
    buffer.writeln(index < 0 ? line : line.substring(0, index));
  }
  return buffer.toString();
}

int _lineOf(String source, int index) {
  var line = 1;
  for (var i = 0; i < index; i += 1) {
    if (source.codeUnitAt(i) == 10) line += 1;
  }
  return line;
}

/// 某个调用名后面紧跟的左括号位置（允许 `Name<T>(` 这种泛型写法）。
int? _callOpenParen(String source, int nameIndex, int nameLength) {
  var i = nameIndex + nameLength;
  if (i < source.length && source[i] == '<') {
    var depth = 0;
    for (; i < source.length; i += 1) {
      if (source[i] == '<') depth += 1;
      if (source[i] == '>') {
        depth -= 1;
        if (depth == 0) {
          i += 1;
          break;
        }
      }
    }
  }
  if (i < source.length && source[i] == '(') return i;
  return null;
}

int? _matchingParen(String source, int openIndex) {
  var depth = 0;
  for (var i = openIndex; i < source.length; i += 1) {
    final ch = source.codeUnitAt(i);
    if (ch == 40) {
      depth += 1;
    } else if (ch == 41) {
      depth -= 1;
      if (depth == 0) return i;
    }
  }
  return null;
}

bool _looksLikeDeclaration(String source, int nameIndex) {
  final start = nameIndex > 80 ? nameIndex - 80 : 0;
  final before = source.substring(start, nameIndex);
  return RegExp(r'(Future|Widget|void|T)\s*(<[^()]*>)?\s*$').hasMatch(before);
}

/// 扫一个文件，返回硬性违规（全部 0 基线，不存在「历史欠账」）。
List<Violation> scanSource(String path, String raw) {
  final source = stripLineComment(raw);
  final violations = <Violation>[];

  for (final entry in bannedPatterns) {
    if (entry.allow.contains(path)) continue;
    // 负向回顾：`AppInkWell(` / `AppTextField(` 这类共享封装自身的调用不算。
    final regex = RegExp('(?<![A-Za-z0-9_\$])${RegExp.escape(entry.pattern)}');
    for (final match in regex.allMatches(source)) {
      violations.add(
        Violation(
          path,
          _lineOf(source, match.start),
          entry.rule,
          entry.message,
        ),
      );
    }
  }

  var showDialogIndex = source.indexOf('showDialog');
  while (showDialogIndex >= 0) {
    final open = _callOpenParen(source, showDialogIndex, 'showDialog'.length);
    if (open != null) {
      violations.add(
        Violation(
          path,
          _lineOf(source, showDialogIndex),
          'no-show-dialog',
          '统一走 showAppDialog',
        ),
      );
    }
    showDialogIndex = source.indexOf('showDialog', showDialogIndex + 10);
  }

  var sheetIndex = source.indexOf('showModalBottomSheet');
  while (sheetIndex >= 0) {
    final open = _callOpenParen(
      source,
      sheetIndex,
      'showModalBottomSheet'.length,
    );
    if (open != null && !sheetAllowlist.contains(path)) {
      violations.add(
        Violation(
          path,
          _lineOf(source, sheetIndex),
          'no-raw-sheet',
          '统一走 showAppSheet',
        ),
      );
    }
    sheetIndex = source.indexOf('showModalBottomSheet', sheetIndex + 20);
  }

  var callIndex = source.indexOf('showAppDialog');
  while (callIndex >= 0) {
    final open = _callOpenParen(source, callIndex, 'showAppDialog'.length);
    if (open != null && !_looksLikeDeclaration(source, callIndex)) {
      final close = _matchingParen(source, open);
      final call = source.substring(callIndex, close ?? source.length);
      if (!call.contains('width:')) {
        violations.add(
          Violation(
            path,
            _lineOf(source, callIndex),
            'dialog-width',
            '业务弹窗要传 width: dialogWidthOf(context)',
          ),
        );
      }
    }
    callIndex = source.indexOf('showAppDialog', callIndex + 14);
  }

  var dropdownIndex = source.indexOf('AppDropdown<');
  while (dropdownIndex >= 0) {
    final open = _callOpenParen(source, dropdownIndex, 'AppDropdown'.length);
    final close = open == null ? null : _matchingParen(source, open);
    if (open != null && close != null) {
      final call = source.substring(dropdownIndex, close);
      if (call.contains("label: '目标") || call.contains('label: "目标')) {
        violations.add(
          Violation(
            path,
            _lineOf(source, dropdownIndex),
            'no-dropdown-target',
            '目标组输入统一走 TargetSelectorField',
          ),
        );
      }
    }
    dropdownIndex = source.indexOf('AppDropdown<', dropdownIndex + 1);
  }

  return violations;
}

/// 递归扫 `lib/ui` 下的 dart 文件。
List<Violation> scanTree(Directory root) {
  final violations = <Violation>[];
  final files =
      root
          .listSync(recursive: true)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));

  for (final file in files) {
    final relative = file.path.replaceAll('\\', '/');
    violations.addAll(scanSource(relative, file.readAsStringSync()));
  }
  violations.sort();
  return violations;
}

void main(List<String> args) {
  final rootPath = _argValue(args, '--root') ?? 'lib/ui';
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    stderr.writeln('找不到目录：$rootPath');
    exit(2);
  }
  if (args.contains('--update-baseline')) {
    stdout.writeln('全部规则为 0 基线，无需更新基线文件。');
    return;
  }
  final violations = scanTree(root);
  if (violations.isEmpty) {
    stdout.writeln('UI 约定检查通过（$rootPath，0 基线）。');
    return;
  }
  stderr.writeln('UI 约定检查失败，共 ${violations.length} 处：');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  stderr.writeln(
    '\n检查规则位于 tool/check_ui_conventions.dart。共享封装见 lib/ui/sheets.dart、'
    'lib/ui/widgets/selectable_tile.dart、lib/ui/app_dialog.dart、'
    'lib/ui/widgets/edit_dialog.dart、lib/ui/widgets/app_ink.dart、'
    'lib/ui/navigation.dart。',
  );
  exit(1);
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
