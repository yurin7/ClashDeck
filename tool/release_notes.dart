// 生成 Release 页面的中文变更报告。
//
// 用法：
//   dart run tool/release_notes.dart --kind release --version 0.3.4 --sha abc1234 --out notes.md
//   dart run tool/release_notes.dart --kind dev --version 0.0.123 --sha abc1234
//
// 正式版从 CHANGELOG.md 抽对应版本段；开发版取最近 12 条提交。
// 纯 Dart、无第三方依赖，解析与渲染拆成纯函数便于单测。

import 'dart:convert';
import 'dart:io';

/// 输出时的固定分类顺序。
const List<String> kCategoryOrder = <String>[
  '新增',
  '修复',
  '改进',
  '性能',
  '重构',
  '移除',
  '测试与构建',
  '其它',
];

/// CHANGELOG 的英文子标题 → 中文分类。
const Map<String, String> kHeadingToCategory = <String, String>{
  'added': '新增',
  'features': '新增',
  'feature': '新增',
  'fixed': '修复',
  'fixes': '修复',
  'fix': '修复',
  'changed': '改进',
  'change': '改进',
  'performance': '性能',
  'refactor': '重构',
  'refactoring': '重构',
  'removed': '移除',
  'deprecated': '移除',
  'tests': '测试与构建',
  'test': '测试与构建',
  'build': '测试与构建',
  'ci': '测试与构建',
};

/// 解析结果：分类 → 原始 bullet 列表，以及是否回退。
class ParsedNotes {
  const ParsedNotes({
    required this.version,
    required this.matchedVersion,
    required this.fallback,
    required this.sections,
  });

  /// 请求的版本号。
  final String version;

  /// 实际取到的 CHANGELOG 版本段（回退时与 [version] 不同）。
  final String matchedVersion;

  /// 是否没找到请求版本、回退了。
  final bool fallback;

  /// 中文分类 → 原始 bullet（含 `- ` 前缀）。
  final Map<String, List<String>> sections;
}

/// 从 CHANGELOG 文本里解析某个版本的分类内容。
///
/// 找不到该版本时依次回退 `Unreleased`、最新一段，并在 [ParsedNotes.fallback]
/// 标记，供渲染层加提示。
ParsedNotes parseChangelog(String source, {required String version}) {
  final sections = <String, List<String>>{};
  String? matched;
  var fallback = false;

  final lines = const LineSplitter().convert(source).toList();
  final headings = <({String label, int index})>[];
  for (var i = 0; i < lines.length; i++) {
    final match = RegExp(r'^## \[(.+?)\]').firstMatch(lines[i]);
    if (match != null) {
      headings.add((label: match.group(1)!.trim(), index: i));
    }
  }
  if (headings.isEmpty) {
    return ParsedNotes(
      version: version,
      matchedVersion: version,
      fallback: true,
      sections: sections,
    );
  }

  var start = headings.indexWhere((h) => h.label == version);
  if (start < 0) {
    fallback = true;
    start = headings.indexWhere((h) => h.label.toLowerCase() == 'unreleased');
    if (start < 0) start = 0;
  }
  final selected = headings[start];
  matched = selected.label;
  final end = start + 1 < headings.length
      ? headings[start + 1].index
      : lines.length;

  String? category;
  for (var i = selected.index + 1; i < end; i++) {
    final line = lines[i];
    final sub = RegExp(r'^###\s+(.+?)\s*$').firstMatch(line);
    if (sub != null) {
      category = _categoryOf(sub.group(1)!);
      continue;
    }
    if (category == null) continue;
    final bullet = RegExp(r'^\s*[-*]\s+(.*)$').firstMatch(line);
    if (bullet == null) continue;
    final text = bullet.group(1)!.trim();
    if (text.isEmpty) continue;
    sections.putIfAbsent(category, () => <String>[]).add('- $text');
  }

  return ParsedNotes(
    version: version,
    matchedVersion: matched,
    fallback: fallback,
    sections: sections,
  );
}

String _categoryOf(String heading) {
  final normalized = heading.trim().toLowerCase();
  // `Tests / CI`、`Fixes (Android)` 这类带后缀的标题按前缀匹配。
  final firstWord = normalized.split(RegExp(r'[\s/（(]')).first;
  final mapped = kHeadingToCategory[firstWord];
  if (mapped != null) return mapped;
  return '其它';
}

/// 渲染正式版变更报告。
String renderReleaseNotes(ParsedNotes notes, {required String sha}) {
  final commit = sha.trim();
  final buffer = StringBuffer()
    ..writeln('## 更新内容（v${notes.version}）')
    ..writeln()
    ..writeln(
      commit.isEmpty
          ? '> 本次发布：正式版 · 版本 ${notes.version}'
          : '> 本次发布：正式版 · 版本 ${notes.version} · 提交 $commit',
    );
  if (notes.fallback) {
    buffer
      ..writeln()
      ..writeln('> 未找到该版本段落，展示最近变更');
  }
  for (final category in kCategoryOrder) {
    final bullets = notes.sections[category];
    if (bullets == null || bullets.isEmpty) continue;
    buffer
      ..writeln()
      ..writeln('### $category')
      ..writeln();
    for (final bullet in bullets) {
      buffer.writeln(bullet);
    }
  }
  return '${buffer.toString().trimRight()}\n';
}

/// 渲染开发版「最近提交」报告；[commits] 为已格式化的行，空列表时只留标题。
String renderDevNotes({
  required String version,
  required String sha,
  required List<String> commits,
}) {
  final buffer = StringBuffer()..writeln('## 最近提交（开发版 $version · $sha）');
  if (commits.isEmpty) {
    return '${buffer.toString().trimRight()}\n';
  }
  buffer.writeln();
  for (final commit in commits) {
    buffer.writeln(commit);
  }
  return '${buffer.toString().trimRight()}\n';
}

/// 读取 `git log` 最近一次提交列表；失败（浅克隆 / 无 git）返回空列表。
List<String> readRecentCommits({String? workingDirectory}) {
  try {
    final result = Process.runSync('git', const <String>[
      'log',
      '--no-merges',
      '-12',
      '--pretty=- %s (%h)',
    ], workingDirectory: workingDirectory);
    if (result.exitCode != 0) return const <String>[];
    return const LineSplitter()
        .convert(result.stdout.toString())
        .where((line) => line.trim().isNotEmpty)
        .toList();
  } catch (_) {
    return const <String>[];
  }
}

Future<void> main(List<String> arguments) async {
  final args = _parseArgs(arguments);
  final kind = args['kind'] ?? 'release';
  final version = args['version'];
  final sha = args['sha'] ?? '';
  final out = args['out'];

  if (version == null || version.isEmpty) {
    stderr.writeln('缺少 --version（正式版填 x.y.z，开发版填 0.0.<run>）');
    exitCode = 64;
    return;
  }

  String notes;
  if (kind == 'dev') {
    notes = renderDevNotes(
      version: version,
      sha: sha,
      commits: readRecentCommits(),
    );
  } else if (kind == 'release') {
    final file = File('CHANGELOG.md');
    if (!file.existsSync()) {
      stderr.writeln('找不到 CHANGELOG.md');
      exitCode = 66;
      return;
    }
    final parsed = parseChangelog(file.readAsStringSync(), version: version);
    notes = renderReleaseNotes(parsed, sha: sha);
  } else {
    stderr.writeln('未知 --kind：$kind（只支持 release / dev）');
    exitCode = 64;
    return;
  }

  if (out == null || out.isEmpty) {
    stdout.write(notes);
  } else {
    File(out).writeAsStringSync(notes);
    stdout.writeln('已写入 $out');
  }
}

Map<String, String> _parseArgs(List<String> arguments) {
  final result = <String, String>{};
  for (var i = 0; i < arguments.length; i++) {
    final arg = arguments[i];
    if (!arg.startsWith('--')) continue;
    final key = arg.substring(2);
    if (i + 1 < arguments.length && !arguments[i + 1].startsWith('--')) {
      result[key] = arguments[i + 1];
      i++;
    } else {
      result[key] = '';
    }
  }
  return result;
}
