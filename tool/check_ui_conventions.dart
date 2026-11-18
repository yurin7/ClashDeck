/// UI 约定自检：扫码 `lib/ui`，拦「绕过共享封装」的写法。
///
/// 规则见 `docs/DESIGN_SYSTEM.md` 第 6 节：
/// 1. 禁止 `Checkbox(` / `CheckboxListTile(`；
/// 2. 只允许 `lib/ui/sheets.dart` 直接调 `showModalBottomSheet(`；
/// 3. 禁止 `showDialog<`；
/// 4. `AlertDialog(` 只允许共享封装 + 基线里已有的历史文件（只减不增）；
/// 5. `showAppDialog(` 必须带 `width:`（同样按基线只减不增）。
///
/// 基线文件：`tool/ui_conventions_baseline.txt`（只减不增）。
/// allowlist 常量在本文件内（`alertAllowlist` / `sheetAllowlist`），
/// **只放共享封装文件**（`lib/ui/app_dialog.dart`、`lib/ui/widgets/edit_dialog.dart`、
/// `lib/ui/sheets.dart`、`lib/ui/widgets/selectable_tile.dart`），业务文件不得加入。
///
/// CI：`.github/workflows/release.yml` 在 Analyze 之后、Test 之前跑
///   dart run tool/check_ui_conventions.dart --check
/// 失败即 fail 整个 job。
///
/// 用法：
///   dart run tool/check_ui_conventions.dart --check
///   dart run tool/check_ui_conventions.dart --update-baseline
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

/// `AlertDialog(` 允许出现的共享封装文件。
///
/// allowlist = 共享封装文件（`lib/ui/app_dialog.dart`、`lib/ui/widgets/edit_dialog.dart`、
/// `lib/ui/sheets.dart`、`lib/ui/widgets/selectable_tile.dart`），业务文件不得加入。
const Set<String> alertAllowlist = <String>{
  'lib/ui/app_dialog.dart',
  'lib/ui/widgets/edit_dialog.dart',
};

/// `showModalBottomSheet(` 允许出现的共享封装文件。
const Set<String> sheetAllowlist = <String>{'lib/ui/sheets.dart'};

const String baselinePath = 'tool/ui_conventions_baseline.txt';

/// 读取基线：`路径 数量` 每行一条，`#` 开头为注释。
Map<String, int> loadBaseline(File file) {
  if (!file.existsSync()) return <String, int>{};
  final result = <String, int>{};
  for (final raw in file.readAsLinesSync()) {
    final line = raw.trim();
    if (line.isEmpty || line.startsWith('#')) continue;
    final parts = line.split(RegExp(r'\s+'));
    if (parts.length < 2) continue;
    final count = int.tryParse(parts.last);
    if (count == null) continue;
    result[parts.first] = count;
  }
  return result;
}

/// 去掉行尾注释，避免注释里的示例触发误报。
String stripLineComment(String source) {
  final buffer = StringBuffer();
  for (final line in source.split('\n')) {
    final index = line.indexOf('//');
    buffer.writeln(index < 0 ? line : line.substring(0, index));
  }
  return buffer.toString();
}

int _occurrences(String source, String pattern) {
  var count = 0;
  var index = source.indexOf(pattern);
  while (index >= 0) {
    count += 1;
    index = source.indexOf(pattern, index + pattern.length);
  }
  return count;
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

/// 扫一个文件，返回硬性违规与按文件计数的两类软指标。
({List<Violation> violations, int alertCount, int widthlessCount}) scanSource(
  String path,
  String raw,
) {
  final source = stripLineComment(raw);
  final violations = <Violation>[];

  for (final pattern in <String>[
    'Checkbox(',
    'Checkbox.adaptive(',
    'CheckboxListTile(',
    'CheckboxListTile.adaptive(',
  ]) {
    var index = source.indexOf(pattern);
    while (index >= 0) {
      violations.add(
        Violation(
          path,
          _lineOf(source, index),
          'no-checkbox',
          '多选改用 SelectableTile',
        ),
      );
      index = source.indexOf(pattern, index + pattern.length);
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

  final alertCount = _occurrences(source, 'AlertDialog(');

  var widthless = 0;
  var callIndex = source.indexOf('showAppDialog');
  while (callIndex >= 0) {
    final open = _callOpenParen(source, callIndex, 'showAppDialog'.length);
    if (open != null && !_looksLikeDeclaration(source, callIndex)) {
      final close = _matchingParen(source, open);
      final call = source.substring(callIndex, close ?? source.length);
      if (!call.contains('width:')) {
        widthless += 1;
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

  return (
    violations: violations,
    alertCount: alertCount,
    widthlessCount: widthless,
  );
}

/// 递归扫 `lib/ui` 下的 dart 文件。
List<Violation> scanTree(
  Directory root, {
  Map<String, int> baseline = const {},
}) {
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
    final scanned = scanSource(relative, file.readAsStringSync());
    final allowedAlert = alertAllowlist.contains(relative)
        ? 100000
        : baseline['$relative#alert'] ?? 0;
    final allowedWidthless = baseline['$relative#widthless'] ?? 0;
    for (final violation in scanned.violations) {
      switch (violation.rule) {
        case 'dialog-width':
          if (scanned.widthlessCount > allowedWidthless) {
            violations.add(violation);
          }
        default:
          violations.add(violation);
      }
    }
    if (scanned.alertCount > allowedAlert) {
      violations.add(
        Violation(relative, 1, 'no-raw-alert', 'AlertDialog 只放在共享封装里'),
      );
    }
  }
  violations.sort();
  return violations;
}

/// 统计当前基线（`--update-baseline` 用）。
Map<String, int> currentBaseline(Directory root) {
  final counts = <String, int>{};
  final files = root
      .listSync(recursive: true)
      .whereType<File>()
      .where((file) => file.path.endsWith('.dart'));
  for (final file in files) {
    final relative = file.path.replaceAll('\\', '/');
    final scanned = scanSource(relative, file.readAsStringSync());
    if (scanned.alertCount > 0 && !alertAllowlist.contains(relative)) {
      counts['$relative#alert'] = scanned.alertCount;
    }
    if (scanned.widthlessCount > 0) {
      counts['$relative#widthless'] = scanned.widthlessCount;
    }
  }
  return counts;
}

void writeBaseline(File file, Map<String, int> counts) {
  final keys = counts.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln('# UI 约定基线：只减不增。改完跑 --update-baseline 收敛。')
    ..writeln('# 格式：<文件>#<规则> <数量>');
  for (final key in keys) {
    buffer.writeln('$key ${counts[key]}');
  }
  file.parent.createSync(recursive: true);
  file.writeAsStringSync(buffer.toString());
}

void main(List<String> args) {
  final rootPath = _argValue(args, '--root') ?? 'lib/ui';
  final root = Directory(rootPath);
  if (!root.existsSync()) {
    stderr.writeln('找不到目录：$rootPath');
    exit(2);
  }
  final update = args.contains('--update-baseline');
  final baselineFile = File(baselinePath);
  if (update) {
    writeBaseline(baselineFile, currentBaseline(root));
    stdout.writeln('已更新基线：$baselinePath');
    return;
  }
  final violations = scanTree(root, baseline: loadBaseline(baselineFile));
  if (violations.isEmpty) {
    stdout.writeln('UI 约定检查通过（$rootPath）。');
    return;
  }
  stderr.writeln('UI 约定检查失败，共 ${violations.length} 处：');
  for (final violation in violations) {
    stderr.writeln('  $violation');
  }
  stderr.writeln(
    '\n规范见 docs/DESIGN_SYSTEM.md；共享封装见 lib/ui/sheets.dart、'
    'lib/ui/widgets/selectable_tile.dart、lib/ui/app_dialog.dart。',
  );
  exit(1);
}

String? _argValue(List<String> args, String name) {
  final index = args.indexOf(name);
  if (index < 0 || index + 1 >= args.length) return null;
  return args[index + 1];
}
