import '../model/profile.dart';
import '../parse/share_link.dart';
import '../yaml/yaml_doc.dart';
import 'config_ops.dart';

/// 一次"批量导入节点"的结果。
class ImportOutcome {
  const ImportOutcome({
    required this.doc,
    required this.added,
    this.renamed = const {},
    this.skipped = const [],
  });

  /// 应用了导入之后的文档（原文档不变）。
  final YamlDoc doc;

  /// 真正写进 `proxies` 的节点名（重名时已被改成 `名字-2` 之类）。
  final List<String> added;

  /// 原名 → 实际写入名，只包含发生改名的。
  final Map<String, String> renamed;

  /// 被跳过的原始名字（只在 skipExisting 时出现）。
  final List<String> skipped;

  bool get isEmpty => added.isEmpty;
  int get count => added.length;
}

/// 在 [taken] 里不冲突的名字：`a`、`a-2`、`a-3` …
String uniqueName(String base, Set<String> taken) {
  final clean = base.trim().isEmpty ? '未命名节点' : base.trim();
  if (!taken.contains(clean)) return clean;
  for (var i = 2; ; i++) {
    final candidate = '$clean-$i';
    if (!taken.contains(candidate)) return candidate;
  }
}

/// 解析一段文本里的分享链接（可多行、可混杂注释与无关行）并写进 `proxies`。
///
/// [group] 非空时，每个新节点还会同时加进这个策略组的显式成员列表。
/// 一条都解析不出来时抛 [ConfigEditException]（保证"失败无副作用"）。
ImportOutcome importLinks(YamlDoc doc, String text, {String? group}) {
  final parsed = parseShareLinks(text);
  if (parsed.isEmpty) {
    throw ConfigEditException(
      '没有解析出可用的节点链接（支持 ${supportedSchemes.join(' / ')}）',
    );
  }
  return importProxies(doc, parsed, group: group);
}

/// 把已经解析好的节点写进 `proxies`（订阅拉回来的、从别的配置里复制的都走这里）。
///
/// 名字会跟现有的节点名、策略组名一起查重——内核要求 `proxies` 与 `proxy-groups`
/// 的 name 全局唯一，撞名会让 `GEOIP,CN,名字` 这类规则指向不明确的东西。
ImportOutcome importProxies(
  YamlDoc doc,
  List<Map<String, Object?>> proxies, {
  String? group,
  bool skipExisting = false,
}) {
  if (proxies.isEmpty) throw ConfigEditException('没有可导入的节点');

  var current = doc;
  final profile = Profile.from(current);
  final taken = <String>{...profile.proxyNames, ...profile.groupNames};
  final added = <String>[];
  final renamed = <String, String>{};
  final skipped = <String>[];

  for (final raw in proxies) {
    final proxy = Map<String, Object?>.from(raw);
    final base = '${proxy['name'] ?? ''}'.trim();
    if (skipExisting && base.isNotEmpty && taken.contains(base)) {
      skipped.add(base);
      continue;
    }
    final name = uniqueName(base, taken);
    if (name != base) renamed[base] = name;
    proxy['name'] = name;
    taken.add(name);
    current = ConfigOps.addProxy(
      current,
      proxy,
      intoGroups: group == null || group.isEmpty ? const [] : [group],
    );
    added.add(name);
  }

  return ImportOutcome(
    doc: current,
    added: added,
    renamed: renamed,
    skipped: skipped,
  );
}
