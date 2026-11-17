import '../model/profile.dart';
import '../model/rule_types.dart';
import '../yaml/yaml_doc.dart';
import 'config_ops.dart';
import '../net/github_mirror.dart';

/// 一次规则导入的结果。只描述「发生了什么」，不负责提示文案的排版。
class RuleImportOutcome {
  const RuleImportOutcome({
    required this.doc,
    required this.rulesAdded,
    required this.rulesSkipped,
    this.rulesRetargeted = 0,
    required this.groupsAdded,
    required this.groupsMerged,
    required this.targetGroupsCreated,
    required this.providersAdded,
    required this.providersUpdated,
    required this.warnings,
  });

  final YamlDoc doc;
  final int rulesAdded;
  final int rulesSkipped;

  /// 同一 provider / code 的旧规则行，目标被就地改写掉的条数。
  final int rulesRetargeted;
  final List<String> groupsAdded;
  final List<String> groupsMerged;

  /// 规则目标在当前配置里不存在时，自动建的 select 组（成员只有 DIRECT）。
  final List<String> targetGroupsCreated;

  /// 顺带合并进来的 `rule-providers` / `proxy-providers`，形如 `rule-providers/cn`。
  final List<String> providersAdded;

  /// 同名 provider 已存在、但 `behavior` 与这次导入不一致而被改写的，形如
  /// `rule-providers/cn`。老配置里写错 behavior 的规则集靠它纠正。
  final List<String> providersUpdated;

  final List<String> warnings;

  bool get isEmpty =>
      rulesAdded == 0 &&
      rulesRetargeted == 0 &&
      groupsAdded.isEmpty &&
      groupsMerged.isEmpty &&
      providersAdded.isEmpty &&
      providersUpdated.isEmpty;

  /// 给 SnackBar 用的一句话总结。
  String get summary {
    final parts = <String>[
      if (rulesAdded > 0) '新增 $rulesAdded 条规则',
      if (rulesSkipped > 0) '跳过 $rulesSkipped 条重复',
      if (rulesRetargeted > 0) '改写 $rulesRetargeted 条目标',
      if (groupsAdded.isNotEmpty) '新建 ${groupsAdded.length} 个策略组',
      if (groupsMerged.isNotEmpty) '补全 ${groupsMerged.length} 个组',
      if (targetGroupsCreated.isNotEmpty)
        '为缺失目标建了 ${targetGroupsCreated.length} 个组',
      if (providersAdded.isNotEmpty) '合并 ${providersAdded.length} 个 provider',
      if (providersUpdated.isNotEmpty) '更新 ${providersUpdated.length} 个同名规则集',
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
  var rulesRetargeted = 0;
  final targetGroupsCreated = <String>[];
  for (final rule in ruleTexts) {
    final profile = Profile.from(next);
    final existing = ConfigOps.ruleStrings(profile).map(_compact).toSet();
    if (existing.contains(_compact(rule))) {
      rulesSkipped++;
      continue;
    }
    // 同一「类型 + 匹配内容」的旧行改目标，而不是再排一条：
    // first-match 下旧行会把新行永久遮住。
    final parts = rule.split(',').map((p) => p.trim()).toList();
    if (parts.length >= 3) {
      final retargeted = _retargetRule(next, parts[0], parts[1], parts[2]);
      if (retargeted != null) {
        if (identical(retargeted, next)) {
          rulesSkipped++;
        } else {
          next = retargeted;
          rulesRetargeted++;
        }
        continue;
      }
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
    rulesRetargeted: rulesRetargeted,
    groupsAdded: groupsAdded,
    groupsMerged: groupsMerged,
    targetGroupsCreated: targetGroupsCreated,
    providersAdded: providersAdded,
    providersUpdated: const [],
    warnings: warnings,
  );
}

/// 把现成的规则行（例如 `GEOSITE,openai,PROXY`）插到 MATCH 之前。
///
/// 和 [importRules] 的区别：调用方已经拿到了最终规则文本，不需要再解析片段或
/// 建 rule-provider；这里只做去重、补缺失目标组、定位插入点。
/// 找到与 [type] + [key] 同一条规则（RULE-SET 按 provider 名、GEOSITE 按 code），
/// 把它的目标就地改成 [target]，位置和顺序都不动。
///
/// 没有这条规则时返回 `null`；已经就是 [target] 时原样返回 [doc]（同一实例），
/// 调用方据此判断「真的改过」还是「本来就是这样」。
YamlDoc? _retargetRule(YamlDoc doc, String type, String key, String target) {
  final wanted = type.toUpperCase();
  List<int> matches(List<String> rules) {
    final hits = <int>[];
    for (var i = 0; i < rules.length; i++) {
      final parts = rules[i].split(',').map((p) => p.trim()).toList();
      if (parts.length < 3) continue;
      if (parts[0].toUpperCase() != wanted) continue;
      if (parts[1] != key) continue;
      hits.add(i);
    }
    return hits;
  }

  var next = doc;
  var hits = matches(ConfigOps.ruleStrings(Profile.from(next)));
  if (hits.isEmpty) return null;

  // 历史配置里同一个 provider 可能已经留了多条（旧版不判重）。先改写第一条，
  // 再把其余重复行删掉：内核 first-match，重复行只会互相遮盖。
  final first = hits.first;
  final parts = ConfigOps.ruleStrings(
    Profile.from(next),
  )[first].split(',').map((p) => p.trim()).toList();
  final changed = parts[2] != target;
  if (changed) {
    // 保留尾部参数（如 no-resolve）。
    final rest = parts.skip(3).join(',');
    next = ConfigOps.updateRule(
      next,
      first,
      rest.isEmpty ? '$type,$key,$target' : '$type,$key,$target,$rest',
    );
  }

  hits = matches(ConfigOps.ruleStrings(Profile.from(next)));
  final hadDuplicates = hits.length > 1;
  if (hadDuplicates) {
    // 从后往前删，避免下标位移。
    for (final index in hits.skip(1).toList().reversed) {
      next = ConfigOps.deleteRule(next, index);
    }
  }
  // 同一实例 = 本来就只有这一条、目标也对，调用方按「跳过」处理。
  if (!changed && !hadDuplicates) return doc;
  return next;
}

RuleImportOutcome insertRuleLines(
  YamlDoc doc,
  List<String> rules, {
  bool createMissingGroups = true,
}) {
  var next = doc;
  final warnings = <String>[];
  final targetGroupsCreated = <String>[];
  var rulesAdded = 0;
  var rulesSkipped = 0;
  var rulesRetargeted = 0;

  for (final raw in rules) {
    final rule = raw.trim();
    if (rule.isEmpty) continue;
    final profile = Profile.from(next);
    final existing = ConfigOps.ruleStrings(profile).map(_compact).toSet();
    if (existing.contains(_compact(rule))) {
      rulesSkipped++;
      continue;
    }
    // 同一「类型 + 匹配内容」的旧行改目标，而不是再排一条：
    // first-match 下旧行会把新行永久遮住。
    final parts = rule.split(',').map((p) => p.trim()).toList();
    if (parts.length >= 3) {
      final retargeted = _retargetRule(next, parts[0], parts[1], parts[2]);
      if (retargeted != null) {
        if (identical(retargeted, next)) {
          rulesSkipped++;
        } else {
          next = retargeted;
          rulesRetargeted++;
        }
        continue;
      }
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
    rulesRetargeted: rulesRetargeted,
    groupsAdded: const [],
    groupsMerged: const [],
    targetGroupsCreated: targetGroupsCreated,
    providersAdded: const [],
    providersUpdated: const [],
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

/// 一份规则集（rule-provider）的内容。
///
/// Loyalsoldier/clash-rules 这类项目的文件都是 `payload:` 列表，两种 behavior：
/// - `direct.txt` / `proxy.txt` / `reject.txt` … → 域名，behavior 用 `domain`
/// - `cncidr.txt` / `telegramcidr.txt` / `lancidr.txt` → IP 段，behavior 用 `ipcidr`
class RuleProviderBody {
  const RuleProviderBody({
    required this.entries,
    required this.behavior,
    this.name,
    this.sourceUrl,
  });

  final List<String> entries;

  /// `domain` 或 `ipcidr`。
  final String behavior;

  /// 从 URL 文件名推出来的建议名字（`direct.txt` → `direct`）。
  final String? name;
  final String? sourceUrl;

  int get count => entries.length;

  bool get isEmpty => entries.isEmpty;
}

/// 解析规则集内容：既接受 `payload:` 的 YAML，也接受纯文本列表（一行一条）。
///
/// 认不出来返回 null；`url` 只用来推断建议名字，不会发起请求。
RuleProviderBody? parseRuleProviderBody(String text, {String? url}) {
  final raw = text.trim();
  if (raw.isEmpty) return null;

  final entries = <String>[];
  String? declaredBehavior;
  String? declaredName;

  final looksYaml = RegExp(
    r'^[ \t]*(payload|behavior|name)[ \t]*:',
    multiLine: true,
  ).hasMatch(raw);
  if (looksYaml) {
    final parsed = YamlDoc.parse(raw);
    if (parsed.isValid) {
      final root = parsed.plainRoot;
      final payload = root['payload'];
      if (payload is List) {
        for (final item in payload) {
          final entry = _cleanProviderEntry('$item');
          if (entry.isNotEmpty) entries.add(entry);
        }
      }
      final behavior = '${root['behavior'] ?? ''}'.trim().toLowerCase();
      if (behavior == 'domain' ||
          behavior == 'ipcidr' ||
          behavior == 'classical') {
        declaredBehavior = behavior;
      }
      final name = '${root['name'] ?? ''}'.trim();
      if (name.isNotEmpty) declaredName = name;
    }
  }

  if (entries.isEmpty) {
    for (final line in raw.split(RegExp(r'\r?\n'))) {
      var value = line.trim();
      if (value.isEmpty || value.startsWith('#')) continue;
      // `payload:` / `rules:` 这种结构行本身不是条目。
      if (RegExp(r'^[A-Za-z_-]+[ \t]*:$').hasMatch(value)) continue;
      // 只去掉 YAML 列表项的「- 」（连字符 + 空白）；
      // 域名规则本身可能以 `-.` 开头（mihomo 的排除写法），不能吃掉这个连字符。
      value = value.replaceFirst(RegExp(r'^-[ \t]+'), '');
      value = _cleanProviderEntry(value);
      if (value.isNotEmpty) entries.add(value);
    }
  }

  if (entries.isEmpty) return null;

  final behavior = declaredBehavior ?? _inferBehavior(entries);
  final urlName = _nameFromUrl(url);
  return RuleProviderBody(
    entries: entries,
    behavior: behavior,
    name: declaredName ?? urlName,
    sourceUrl: url,
  );
}

String _cleanProviderEntry(String value) {
  var v = value.trim();
  if (v.length >= 2) {
    final first = v[0];
    final last = v[v.length - 1];
    if ((first == "'" && last == "'") || (first == '"' && last == '"')) {
      v = v.substring(1, v.length - 1).trim();
    }
  }
  return v;
}

final RegExp _cidrV4 = RegExp(r'^(\d{1,3}\.){3}\d{1,3}(/\d{1,2})?$');
final RegExp _cidrV6 = RegExp(r'^[0-9a-fA-F:]+/\d{1,3}$');

/// 猜一条 payload 列表的 behavior。
///
/// - 全是 IP / CIDR → `ipcidr`
/// - 大半是 `DOMAIN-SUFFIX,xx` 这种带类型的规则行 → `classical`
///   （ACL4SSR 的 `.list` 就是这种，写成 `domain` 会被内核判成非法）
/// - 其余 → `domain`
String _inferBehavior(List<String> entries) {
  final allIp = entries.every(
    (e) => _cidrV4.hasMatch(e) || _cidrV6.hasMatch(e),
  );
  if (allIp) return 'ipcidr';
  final ruleLines = entries.where(_looksLikeRuleLine).length;
  if (ruleLines * 2 >= entries.length) return 'classical';
  return 'domain';
}

/// 判断一行是不是 `DOMAIN-SUFFIX,example.com` 这类完整规则。
bool _looksLikeRuleLine(String entry) {
  final comma = entry.indexOf(',');
  if (comma <= 0) return false;
  final type = entry.substring(0, comma);
  if (!type.contains(RegExp(r'[A-Z]'))) return false;
  return type
      .split('-')
      .every((part) => part.isNotEmpty && part.toUpperCase() == part);
}

String? _nameFromUrl(String? url) {
  if (url == null || url.trim().isEmpty) return null;
  final uri = Uri.tryParse(url.trim());
  if (uri == null) return null;
  final segments = uri.pathSegments.where((s) => s.isNotEmpty).toList();
  if (segments.isEmpty) return null;
  var name = segments.last;
  for (final ext in const ['.txt', '.yaml', '.yml', '.list', '.conf']) {
    if (name.toLowerCase().endsWith(ext)) {
      name = name.substring(0, name.length - ext.length);
      break;
    }
  }
  name = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '-');
  return name.isEmpty ? null : name;
}

/// 把一份规则集写进 `rule-providers`，并在兜底规则之前加一条 `RULE-SET`。
///
/// - 给了 [url]：写成 `type: http`（内核按 interval 自动更新），path 用
///   `./ruleset/<name>.yaml`，和社区配置的习惯一致；
/// - 没给 URL：写成 `type: inline`，条目直接嵌进配置。
RuleImportOutcome importRuleProvider(
  YamlDoc doc, {
  required RuleProviderBody body,
  required String name,
  required String target,
  String? url,
  bool createMissingGroups = true,
  int interval = 86400,
  String? groupName,
  List<String> groupMembers = const [],
}) {
  final providerName = name.trim();
  final targetName = target.trim();
  if (providerName.isEmpty) throw ConfigEditException('规则集需要一个名字');
  if (targetName.isEmpty) throw ConfigEditException('规则集需要一个策略组作为目标');
  if (body.isEmpty) throw ConfigEditException('规则集是空的');

  var next = doc;
  final warnings = <String>[];
  final providersAdded = <String>[];
  final providersUpdated = <String>[];
  final groupsAdded = <String>[];
  final groupsMerged = <String>[];
  // 「创建同名节点组」勾上时，规则集的目标换成这个组。
  var effectiveTarget = targetName;

  final existingProviders = next.plainAt(const ['rule-providers']);
  final existing = existingProviders is Map
      ? existingProviders[providerName]
      : null;
  if (existing is Map) {
    // 同名 provider 已存在：behavior 一致就沿用，不一致就纠正。
    // 老配置里 ACL4SSR 这类 classical 列表曾被写成 domain，内核按 domain
    // 解析带类型前缀的行会失败，所以这里必须覆盖而不是静默跳过。
    final current = existing['behavior'];
    final currentBehavior = current is String ? current : null;
    final existingUrl = existing['url'];
    final currentUrl = existingUrl is String ? existingUrl.trim() : '';
    // 手机上的内核运行时也要来拉这个 provider，raw.githubusercontent
    // 在国内经常拉不动，所以落盘一律写成镜像地址；老配置里的直连地址
    // 也要借这次导入顺手纠正，否则内核跑起来还是拉不动。
    final wantedUrl = url == null || url.trim().isEmpty
        ? currentUrl
        : GithubMirror.preferred(url);
    final behaviorChanged = currentBehavior != body.behavior;
    final urlChanged = wantedUrl.isNotEmpty && wantedUrl != currentUrl;
    if (!behaviorChanged && !urlChanged) {
      warnings.add('rule-providers 里已有「$providerName」，沿用原有定义');
    } else {
      final merged = <String, Object?>{
        for (final entry in existing.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      if (behaviorChanged) merged['behavior'] = body.behavior;
      if (wantedUrl.isNotEmpty) {
        merged['type'] = 'http';
        merged['url'] = wantedUrl;
        merged['path'] = merged['path'] ?? './ruleset/$providerName.yaml';
        merged['interval'] = merged['interval'] ?? interval;
      }
      next = ConfigOps.setAtOrCreate(next, [
        'rule-providers',
        providerName,
      ], merged);
      providersUpdated.add('rule-providers/$providerName');
      if (behaviorChanged) {
        warnings.add(
          '「$providerName」的 behavior 从 ${currentBehavior ?? '未写'} '
          '改成 ${body.behavior}（旧定义会让内核解析失败）',
        );
      }
      if (urlChanged) {
        warnings.add('「$providerName」的地址换成镜像（内核运行时也要拉得动）');
      }
    }
  } else {
    final Map<String, Object?> provider;
    if (url != null && url.trim().isNotEmpty) {
      provider = {
        'type': 'http',
        'behavior': body.behavior,
        'url': GithubMirror.preferred(url),
        'path': './ruleset/$providerName.yaml',
        'interval': interval,
      };
    } else {
      provider = {
        'type': 'inline',
        'behavior': body.behavior,
        'payload': body.entries,
      };
    }
    next = ConfigOps.setAtOrCreate(next, [
      'rule-providers',
      providerName,
    ], provider);
    providersAdded.add('rule-providers/$providerName');
  }

  final targetGroupsCreated = <String>[];
  final wantedGroup = (groupName ?? '').trim();
  if (wantedGroup.isNotEmpty) {
    // 先按名字找：已存在就复用，避免把用户调好的成员覆盖掉。
    if (Profile.from(next).group(wantedGroup) != null) {
      groupsMerged.add(wantedGroup);
    } else {
      final members = groupMembers.isEmpty ? const ['DIRECT'] : groupMembers;
      try {
        next = ConfigOps.addGroup(next, {
          'name': wantedGroup,
          'type': 'select',
        }, members: members);
        groupsAdded.add(wantedGroup);
      } on ConfigEditException catch (e) {
        warnings.add('无法创建策略组「$wantedGroup」：${e.message}');
      }
    }
    effectiveTarget = wantedGroup;
  }

  if (createMissingGroups) {
    final profile = Profile.from(next);
    final known =
        Profile.builtinTargets.contains(effectiveTarget) ||
        profile.proxy(effectiveTarget) != null ||
        profile.group(effectiveTarget) != null;
    if (!known) {
      try {
        next = ConfigOps.addGroup(
          next,
          {'name': effectiveTarget, 'type': 'select'},
          members: const ['DIRECT'],
        );
        targetGroupsCreated.add(effectiveTarget);
      } on ConfigEditException catch (e) {
        warnings.add('无法为规则目标「$effectiveTarget」建组：${e.message}');
      }
    }
  }

  final rule = 'RULE-SET,$providerName,$effectiveTarget';
  final profileNow = Profile.from(next);
  var rulesAdded = 0;
  var rulesSkipped = 0;
  var rulesRetargeted = 0;
  // 内核规则自上而下 first-match：同一个 provider 留两条不同目标的规则，
  // 旧行会把新行永久遮住。所以先按 provider 名找旧行，找到就就地改写目标。
  final retargeted = _retargetRule(
    next,
    'RULE-SET',
    providerName,
    effectiveTarget,
  );
  if (retargeted != null) {
    if (identical(retargeted, next)) {
      rulesSkipped = 1;
    } else {
      next = retargeted;
      rulesRetargeted = 1;
    }
  } else {
    final terminalAt = profileNow.rules.indexWhere((r) => r.isTerminal);
    next = ConfigOps.addRule(
      next,
      rule,
      at: terminalAt < 0 ? null : terminalAt,
    );
    rulesAdded = 1;
  }

  return RuleImportOutcome(
    doc: next,
    rulesAdded: rulesAdded,
    rulesSkipped: rulesSkipped,
    rulesRetargeted: rulesRetargeted,
    groupsAdded: groupsAdded,
    groupsMerged: groupsMerged,
    targetGroupsCreated: targetGroupsCreated,
    providersAdded: providersAdded,
    providersUpdated: providersUpdated,
    warnings: warnings,
  );
}
