import '../core/yaml/yaml_doc.dart';

/// 系统内置策略：没有自己的服务器地址，不能做 TCP 探测。
const Set<String> kBuiltinPolicyNames = {
  'DIRECT',
  'REJECT',
  'REJECT-DROP',
  'PASS',
  'COMPATIBLE',
  'GLOBAL',
};

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

/// 内核没运行时做 TCP 近似测速的目标：节点名 → `server:port`。
///
/// 跳过内置策略（DIRECT / REJECT 等）、协议组以及 `server` / `port`
/// 缺失或非法的条目，避免把「策略名」当成服务器去连。
Map<String, ({String host, int port})> tcpTargetsFrom(YamlDoc doc) {
  final raw = doc.plainAt(['proxies']);
  if (raw is! List) return const <String, ({String host, int port})>{};
  final targets = <String, ({String host, int port})>{};
  for (final entry in raw) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is! String || name.isEmpty) continue;
    if (kBuiltinPolicyNames.contains(name.toUpperCase())) continue;
    final host = '${entry['server'] ?? ''}'.trim();
    if (host.isEmpty) continue;
    final rawPort = entry['port'];
    final port = rawPort is int
        ? rawPort
        : (rawPort is String ? int.tryParse(rawPort) : null);
    if (port == null || port <= 0 || port > 65535) continue;
    targets[name] = (host: host, port: port);
  }
  return targets;
}

/// UI 入口是否允许测速：有节点、当前没在测。
bool canTestDelay({required bool hasNodes, required bool testing}) =>
    hasNodes && !testing;
