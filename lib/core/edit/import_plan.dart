/// 导入预览：先把「会发生什么」算出来给用户看，确认后再按同一份结果写入。
///
/// 这里的函数都是纯函数，方便单测；真正写配置仍然由 `import_rules.dart` 负责。
library;

import 'config_ops.dart';

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

/// GEOSITE code 的合法形状：内核只认小写字母、数字和短横线。
final RegExp _geositeCodePattern = RegExp(r'^[a-z0-9-]+$');

/// 精选词库里还有 `category-ai-!cn` 这种带感叹号的分类名，
/// 它们写进规则行是安全的，不能按上面的严格形状拦掉。
final RegExp _geositeSafePattern = RegExp(r'^[a-z0-9!-]+$');

/// 能不能直接写进 `GEOSITE,<code>`；用户手输的 code 先过这一关。
bool isValidGeositeCode(String code) =>
    _geositeCodePattern.hasMatch(code.trim());

/// 能不能安全地拼进规则行：只拦会破坏 `GEOSITE,<code>,<target>` 的字符。
bool _isSafeGeositeCode(String code) => _geositeSafePattern.hasMatch(code);

/// 一次批量 GEO 导入的预估结果。
class GeositePlan {
  const GeositePlan({
    this.rules = const [],
    this.skipped = const [],
    this.invalid = const [],
  });

  /// 要写入的 `GEOSITE,<code>,<target>` 规则行，顺序与输入一致。
  final List<String> rules;

  /// 配置里已经有、直接跳过的 code。
  final List<String> skipped;

  /// 形状不合法的输入（原样保留，方便提示用户）。
  final List<String> invalid;

  bool get isEmpty => rules.isEmpty;
}

/// 批量 GEO 导入的计划：去重、跳过已存在、丢弃非法 code。
///
/// 目标组统一 [target]（默认 [kDefaultGroupName]），不再为每个词库新建同名组。
GeositePlan planGeositeRules({
  required Iterable<String> codes,
  Iterable<String> existingCodes = const [],
  String target = kDefaultGroupName,
}) {
  final group = target.trim().isEmpty ? kDefaultGroupName : target.trim();
  final existing = {
    for (final code in existingCodes) code.trim().toLowerCase(),
  };
  final seen = <String>{};
  final rules = <String>[];
  final skipped = <String>[];
  final invalid = <String>[];
  for (final raw in codes) {
    final code = raw.trim().toLowerCase();
    if (code.isEmpty) continue;
    if (!_isSafeGeositeCode(code)) {
      invalid.add(raw.trim());
      continue;
    }
    if (!seen.add(code)) continue;
    if (existing.contains(code)) {
      skipped.add(code);
      continue;
    }
    rules.add('GEOSITE,$code,$group');
  }
  return GeositePlan(rules: rules, skipped: skipped, invalid: invalid);
}
