/// 导入预览：先把「会发生什么」算出来给用户看，确认后再按同一份结果写入。
///
/// 这里的函数都是纯函数，方便单测；真正写配置仍然由 `import_rules.dart` 负责。
library;

/// 规范化规则集地址，用来判断「是不是同一个规则集」。
///
/// 同一个 provider 在不同来源里经常长这样：
///
/// - `https://raw.githubusercontent.com/a/b/main/x.txt@master`
/// - `https://raw.githubusercontent.com/a/b/main/x.txt/`
/// - `https://raw.githubusercontent.com/a/b/main/x.txt?token=1`
///
/// 去掉分支后缀、query 和末尾斜杠之后视为同一个。
String normalizeRuleSetUrl(String url) {
  var text = url.trim();
  if (text.isEmpty) return '';
  // 去掉分支版本后缀：`...txt@master` / `...txt@release`。
  final at = text.lastIndexOf('@');
  if (at > 0) {
    final tail = text.substring(at + 1);
    if (tail.isNotEmpty && !tail.contains('/') && !tail.contains('?')) {
      text = text.substring(0, at);
    }
  }
  final q = text.indexOf('?');
  if (q >= 0) text = text.substring(0, q);
  final hash = text.indexOf('#');
  if (hash >= 0) text = text.substring(0, hash);
  while (text.endsWith('/')) {
    text = text.substring(0, text.length - 1);
  }
  return text;
}

/// 归一化显示名：小写、只留字母数字，避免标点/空格造成假的不相等。
String normalizeDisplayName(String name) =>
    name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Levenshtein 编辑距离（只用于「看起来像同一个」的提示，不追求性能）。
int nameEditDistance(String a, String b) {
  final left = normalizeDisplayName(a);
  final right = normalizeDisplayName(b);
  if (left == right) return 0;
  if (left.isEmpty) return right.length;
  if (right.isEmpty) return left.length;
  var prev = List<int>.generate(right.length + 1, (i) => i);
  for (var i = 1; i <= left.length; i++) {
    final row = List<int>.filled(right.length + 1, 0);
    row[0] = i;
    for (var j = 1; j <= right.length; j++) {
      final cost = left[i - 1] == right[j - 1] ? 0 : 1;
      var best = prev[j] + 1;
      if (row[j - 1] + 1 < best) best = row[j - 1] + 1;
      if (prev[j - 1] + cost < best) best = prev[j - 1] + cost;
      row[j] = best;
    }
    prev = row;
  }
  return prev[right.length];
}

/// 名字接近到「很可能就是同一个」的程度。
bool looksLikeSameName(String a, String b) {
  final left = normalizeDisplayName(a);
  final right = normalizeDisplayName(b);
  if (left.isEmpty || right.isEmpty) return false;
  if (left == right) return true;
  return nameEditDistance(left, right) <= 2;
}

/// 一次导入的预估结果。`confirmed` 之后才真正写配置。
class ImportPlan {
  const ImportPlan({
    this.newGroups = const [],
    this.reusedGroups = const [],
    this.newProviders = const [],
    this.updatedProviders = const [],
    this.skippedRules = 0,
    this.rulesToAdd = 0,
    this.similarNames = const {},
  });

  /// 会新建的节点组名。
  final List<String> newGroups;

  /// 复用已有节点组的名字。
  final List<String> reusedGroups;

  /// 会新增的 rule-provider 名。
  final List<String> newProviders;

  /// 会覆盖更新的 rule-provider 名。
  final List<String> updatedProviders;

  /// 因为已存在（规则重复 / provider 内容完全一样）会跳过的条数。
  final int skippedRules;

  /// 会新增的规则条数。
  final int rulesToAdd;

  /// 疑似重名：新名字 -> 已有名字。
  final Map<String, String> similarNames;

  bool get isEmpty =>
      rulesToAdd == 0 &&
      newProviders.isEmpty &&
      updatedProviders.isEmpty &&
      skippedRules == 0;

  /// 给确认弹窗用的多行摘要。
  String get summary {
    final lines = <String>[];
    if (rulesToAdd > 0) lines.add('新增规则 $rulesToAdd 条');
    if (newProviders.isNotEmpty) lines.add('新建规则集 ${newProviders.length} 个');
    if (updatedProviders.isNotEmpty) {
      lines.add('更新规则集 ${updatedProviders.length} 个');
    }
    if (newGroups.isNotEmpty) lines.add('新建节点组 ${newGroups.length} 个');
    if (reusedGroups.isNotEmpty) lines.add('复用节点组 ${reusedGroups.length} 个');
    if (skippedRules > 0) lines.add('跳过重复 $skippedRules 条');
    if (similarNames.isNotEmpty) {
      lines.add('疑似重名 ${similarNames.length} 处');
    }
    if (lines.isEmpty) return '没有需要写入的内容。';
    return lines.join(' · ');
  }

  /// 疑似重名的可读列表，给「复用已有 / 新建」二选一用。
  List<String> get similarLines => [
    for (final entry in similarNames.entries) '${entry.key} ≈ ${entry.value}',
  ];
}
