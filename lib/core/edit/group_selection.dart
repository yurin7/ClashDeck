import '../model/profile.dart';
import 'member_order.dart';

/// 组内「当前选中的节点」的判定规则。
///
/// 记住的选择只有在**仍是组内成员**时才有效（成员删掉后必须自动回落，
/// 否则删光再加节点会没有任何高亮）；否则按 [defaultGroupSelection] 规范
/// 自动选一个：代理节点优先，其次 DIRECT，再 REJECT。
String? selectedInGroup(
  Map<String, String> saved,
  GroupEntry group, {
  List<String> proxyOrder = const <String>[],
}) {
  return defaultGroupSelection(
    group.members,
    proxyOrder: proxyOrder,
    saved: saved[group.name],
  );
}

/// 按 [selectedInGroup] 规则取出一份选择的快照，供渲染用。
///
/// 不依赖运行时：停止状态下也能显示「上次选的是谁」，运行中再以运行时的
/// 实际选择覆盖（运行时会话内的切换不会回写 sidecar）。
Map<String, String> groupSelectionSnapshot(
  Profile profile,
  Map<String, String> saved,
) {
  final proxyOrder = [for (final proxy in profile.proxies) proxy.name];
  return <String, String>{
    for (final group in profile.groups)
      if (selectedInGroup(saved, group, proxyOrder: proxyOrder)
          case final String name)
        group.name: name,
  };
}

/// 从 sidecar meta 里取出 `app.groupNodes`（组 → 成员名）。
Map<String, String> groupNodesOf(Map<String, Object?> meta) {
  final app = meta['app'];
  final raw = app is Map ? app['groupNodes'] : null;
  if (raw is! Map) return const <String, String>{};
  return <String, String>{
    for (final entry in raw.entries)
      if (entry.key is String && entry.value is String)
        entry.key as String: entry.value as String,
  };
}

/// 把一次组内选择合并进 sidecar meta，返回新的 meta（不改原 map）。
///
/// 只动 `app.groupNodes`，`app` 里的其它键（全局出口、自动保存等）和
/// 顶层的 `subscriptionUrl` 都原样保留。
Map<String, Object?> withGroupNode(
  Map<String, Object?> meta,
  String group,
  String node,
) {
  final app = meta['app'] is Map
      ? Map<String, Object?>.from(meta['app']! as Map)
      : <String, Object?>{};
  final nodes = app['groupNodes'] is Map
      ? Map<String, Object?>.from(app['groupNodes']! as Map)
      : <String, Object?>{};
  nodes[group] = node;
  app['groupNodes'] = nodes;
  return <String, Object?>{...meta, 'app': app};
}
