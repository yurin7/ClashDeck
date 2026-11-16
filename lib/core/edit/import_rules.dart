import '../model/profile.dart';
import '../model/rule_types.dart';
import '../yaml/yaml_doc.dart';
import 'config_ops.dart';

/// 一次规则导入的结果。只描述「发生了什么」，不负责提示文案的排版。
class RuleImportOutcome {
  const RuleImportOutcome({
    required this.doc,
    required this.rulesAdded,
    required this.rulesSkipped,
    required this.groupsAdded,
    required this.groupsMerged,
    required this.targetGroupsCreated,
    required this.providersAdded,
    required this.warnings,
  });

  final YamlDoc doc;
  final int rulesAdded;
  final int rulesSkipped;
  final List<String> groupsAdded;
  final List<String> groupsMerged;

  /// 规则目标在当前配置里不存在时，自动建的 select 组（成员只有 DIRECT）。
  final List<String> targetGroupsCreated;

  /// 顺带合并进来的 `rule-providers` / `proxy-providers`，形如 `rule-providers/cn`。
  final List<String> providersAdded;

  final List<String> warnings;

  bool get isEmpty =>
      rulesAdded == 0 &&
      groupsAdded.isEmpty &&
      groupsMerged.isEmpty &&
      providersAdded.isEmpty;

  /// 给 SnackBar 用的一句话总结。
  String get summary {
    final parts = <String>[
      if (rulesAdded > 0) '新增 $rulesAdded 条规则',
      if (rulesSkipped > 0) '跳过 $rulesSkipped 条重复',
      if (groupsAdded.isNotEmpty) '新建 ${groupsAdded.length} 个策略组',
      if (groupsMerged.isNotEmpty) '补全 ${groupsMerged.length} 个组',
      if (targetGroupsCreated.isNotEmpty)
        '为缺失目标建了 ${targetGroupsCreated.length} 个组',
      if (providersAdded.isNotEmpty) '合并 ${providersAdded.length} 个 provider',
      if (warnings.isNotEmpty) '${warnings.length} 条提示',
    ];
    return parts.isEmpty ? '没有可导入的内容' : parts.join(' · ');
  }
}

/// 从粘贴的文本里导入规则，并尽量把附带的策略组一起带进来。
///
/// 支持的输入：
/// 1. 纯规则行（每行 `类型,匹配,目标[,no-resolve]`，允许 `- ` 前缀与 `#` 注释行）；
/// 2. Clash 配置片段（含 `rules:` / `proxy-groups:` / `rule-providers:`
///    / `proxy-providers:`），策略组与 provider 会一起合并；
/// 3. 以上两者混在一起（先按 YAML 试，解析不出再用逐行文本）。
///
/// 规则总是插到兜底规则（MATCH/FINAL）之前；重复的规则跳过。
RuleImportOutcome importRules(
  YamlDoc doc,
  String text, {
  bool createMissingGroups = true,
}) {
  final raw = text.trim();
  if (raw.isEmpty) throw ConfigEditException('没有可导入的内容');

  final warnings = <String>[];
  final ruleTexts = <String>[];
  final groupMaps = <Map<String, Object?>>[];
  final providers = <String, Object?>{};

  _readYamlFragment(raw, ruleTexts, groupMaps, providers, warnings);
  if (ruleTexts.isEmpty && groupMaps.isEmpty && providers.isEmpty) {
    // 不像 YAML（或没有任何结构），当成纯文本规则看。
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      final normalized = _normalizeRuleLine(line, warnings);
      if (normalized != null) ruleTexts.add(normalized);
    }
  }

  if (ruleTexts.isEmpty && groupMaps.isEmpty && providers.isEmpty) {
    throw ConfigEditException(
      warnings.isEmpty ? '没找到可导入的规则或策略组' : '没找到可导入的规则或策略组：${warnings.first}',
    );
  }

  var next = doc;

  // 1) provider 先合并，规则里的 RULE-SET 才有东西可用。
  final providersAdded = <String>[];
  for (final entry in providers.entries) {
    final slash = entry.key.indexOf('/');
    final key = entry.key.substring(0, slash);
    final name = entry.key.substring(slash + 1);
    final existing = next.plainAt([key]);
    if (existing is Map && existing.containsKey(name)) {
      warnings.add('$key 里已有「$name」，未覆盖');
      continue;
    }
    next = ConfigOps.setAtOrCreate(next, [key, name], entry.value);
    providersAdded.add('$key/$name');
  }

  // 2) 再合并策略组（成员里引用了不存在的节点/组就跳过）。
  final groupsAdded = <String>[];
  final groupsMerged = <String>[];
  for (final group in groupMaps) {
    final name = '${group['name'] ?? ''}'.trim();
    final type = '${group['type'] ?? ''}'.trim();
    if (name.isEmpty || type.isEmpty) {
      warnings.add('跳过缺少 name/type 的策略组');
      continue;
    }
    final profile = Profile.from(next);
    final members = <String>[];
    final declared = group['proxies'];
    if (declared is List) {
      for (final member in declared) {
        final m = '$member'.trim();
        if (m.isEmpty) continue;
        if (profile.proxy(m) != null || profile.group(m) != null) {
          members.add(m);
        } else {
          warnings.add('「$name」的成员「$m」在当前配置里不存在，已跳过');
        }
      }
    }
    if (profile.group(name) == null) {
      final map = Map<String, Object?>.from(group)..remove('proxies');
      map['name'] = name;
      map['type'] = type;
      next = ConfigOps.addGroup(next, map, members: members);
      groupsAdded.add(name);
    } else {
      var added = 0;
      for (final member in members) {
        final current = Profile.from(next).group(name);
        if (current == null || current.members.contains(member)) continue;
        next = ConfigOps.addGroupMember(next, name, member);
        added++;
      }
      if (added > 0) groupsMerged.add(name);
    }
  }

  // 3) 最后追加规则。
  var rulesAdded = 0;
  var rulesSkipped = 0;
  final targetGroupsCreated = <String>[];
  for (final rule in ruleTexts) {
    final profile = Profile.from(next);
    final existing = ConfigOps.ruleStrings(profile).map(_compact).toSet();
    if (existing.contains(_compact(rule))) {
      rulesSkipped++;
      continue;
    }
    if (createMissingGroups) {
      final entry = RuleEntry.parse(profile.rules.length, rule);
      final target = entry.target;
      final known =
          target.isEmpty ||
          Profile.builtinTargets.contains(target) ||
          profile.proxy(target) != null ||
          profile.group(target) != null;
      if (!known) {
        try {
          next = ConfigOps.addGroup(
            next,
            {'name': target, 'type': 'select'},
            members: const ['DIRECT'],
          );
          targetGroupsCreated.add(target);
        } on ConfigEditException catch (e) {
          warnings.add('无法为规则目标「$target」建组：${e.message}');
        }
      }
    }
    final terminalAt = Profile.from(next).rules.indexWhere((r) => r.isTerminal);
    next = ConfigOps.addRule(
      next,
      rule,
      at: terminalAt < 0 ? null : terminalAt,
    );
    rulesAdded++;
  }

  return RuleImportOutcome(
    doc: next,
    rulesAdded: rulesAdded,
    rulesSkipped: rulesSkipped,
    groupsAdded: groupsAdded,
    groupsMerged: groupsMerged,
    targetGroupsCreated: targetGroupsCreated,
    providersAdded: providersAdded,
    warnings: warnings,
  );
}

/// 试读 YAML 片段；不是 YAML 或者解析失败时什么都不加（交给逐行文本兜底）。
void _readYamlFragment(
  String text,
  List<String> ruleTexts,
  List<Map<String, Object?>> groupMaps,
  Map<String, Object?> providers,
  List<String> warnings,
) {
  final looksStructured = RegExp(
    r'^[ \t]*(rules|proxy-groups|rule-providers|proxy-providers)[ \t]*:',
    multiLine: true,
  ).hasMatch(text);
  if (!looksStructured) return;

  final parsed = YamlDoc.parse(text);
  if (!parsed.isValid) {
    warnings.add('按 YAML 解析失败（${parsed.error?.message}），改用逐行解析');
    return;
  }
  final root = parsed.plainRoot;

  final rules = root['rules'];
  if (rules is List) {
    for (final item in rules) {
      final s = '$item'.trim();
      if (s.isNotEmpty) ruleTexts.add(s);
    }
  }

  final groups = root['proxy-groups'];
  if (groups is List) {
    for (final item in groups) {
      if (item is Map) {
        groupMaps.add(item.map((key, value) => MapEntry('$key', value)));
      } else {
        warnings.add('跳过无法识别的策略组条目：$item');
      }
    }
  }

  for (final key in const ['rule-providers', 'proxy-providers']) {
    final map = root[key];
    if (map is! Map) continue;
    for (final entry in map.entries) {
      providers['$key/${entry.key}'] = entry.value;
    }
  }
}

/// 校验并规整一行规则；认不出来就记一条提示并返回 null。
String? _normalizeRuleLine(String rawLine, List<String> warnings) {
  var line = rawLine.trim();
  if (line.isEmpty || line.startsWith('#')) return null;
  // 允许直接粘贴 YAML 列表项（`- DOMAIN,x,y`）。
  if (line.startsWith('- ')) line = line.substring(2).trim();
  if (line.isEmpty) return null;
  // `rules:` 这类结构行不是规则。
  if (line.endsWith(':') && !line.contains(',')) {
    warnings.add('跳过结构行：$rawLine');
    return null;
  }

  final parts = line.split(',').map((p) => p.trim()).toList();
  final type = normalizeRuleType(parts.first);
  if (!isKnownRuleType(type)) {
    warnings.add('不是已知规则类型，已跳过：$rawLine');
    return null;
  }
  if (kTerminalRuleTypes.contains(type)) {
    if (parts.length < 2 || parts[1].isEmpty) {
      warnings.add('兜底规则缺少目标，已跳过：$rawLine');
      return null;
    }
    return [type, ...parts.skip(1)].join(',');
  }
  if (parts.length < 3 || parts[1].isEmpty || parts[2].isEmpty) {
    warnings.add('规则不完整（需要 类型,匹配,目标），已跳过：$rawLine');
    return null;
  }
  return [type, ...parts.skip(1)].join(',');
}

/// 去重用的归一化形式：类型小写 + 去掉多余空格。
String _compact(String rule) => rule
    .split(',')
    .map((p) => p.trim())
    .map((p) => p.isEmpty ? p : p)
    .join(',')
    .toLowerCase();
