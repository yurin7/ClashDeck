import '../core/yaml/yaml_doc.dart';

/// 从配置里取出可以测速的节点名（`proxies:` 里每项的 `name`）。
///
/// 「自动选择」等策略组不参与：它们没有自己的延迟，出口由成员决定。
List<String> delayTargetsFrom(YamlDoc doc) {
  final raw = doc.plainAt(['proxies']);
  if (raw is! List) return const <String>[];
  final names = <String>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is String && name.isNotEmpty) names.add(name);
  }
  return names;
}
