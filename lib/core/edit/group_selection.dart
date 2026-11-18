import '../model/profile.dart';

/// 组内「当前选中的节点」的判定规则。
///
/// 顺序：sidecar 里记住的选择 → 组内第一个成员 → 无成员时为 null。
/// 记住的选择可能已经被删掉（节点移除、组改名），所以这里不做存在性校验，
/// 只保证「有就优先用」，由调用方决定找不到时怎么回落。
String? selectedInGroup(Map<String, String> saved, GroupEntry group) {
  final picked = saved[group.name];
  if (picked != null && picked.isNotEmpty) return picked;
  return group.members.isEmpty ? null : group.members.first;
}

/// 按 [selectedInGroup] 规则取出一份选择的快照，供渲染用。
///
/// 不依赖运行时：停止状态下也能显示「上次选的是谁」，运行中再以运行时的
/// 实际选择覆盖（运行时会话内的切换不会回写 sidecar）。
Map<String, String> groupSelectionSnapshot(
  Profile profile,
  Map<String, String> saved,
) {
  return <String, String>{
    for (final group in profile.groups)
      if (selectedInGroup(saved, group) case final String name)
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
