import '../model/profile.dart';

/// 组卡头上「当前出口」这一行要显示什么。
///
/// - `load-balance`：内核按连接自动分摊，没有单一出口 → 显示节点数；
/// - `url-test`：取已测延迟里最低的那个，附「最低延迟」；
/// - `fallback`：优先最低延迟，没数据就退回运行时选中的成员；
/// - 其它（select/DEFAULT/relay）：直接用运行时选中的成员。
///
/// 返回 null 表示这一行不显示。
String? groupCurrentLabel({
  required GroupEntry group,
  required Map<String, int?> delays,
  String? selectedName,
}) {
  if (group.type == 'load-balance') {
    return group.members.isEmpty ? null : '自动均衡 · ${group.members.length} 节点';
  }
  if (group.type != 'url-test' && group.type != 'fallback') {
    return selectedName != null && group.members.contains(selectedName)
        ? '当前 $selectedName'
        : null;
  }
  String? best;
  int? bestDelay;
  for (final name in group.members) {
    final delay = delays[name];
    if (delay == null) continue;
    if (bestDelay == null || delay < bestDelay) {
      best = name;
      bestDelay = delay;
    }
  }
  best ??= selectedName != null && group.members.contains(selectedName)
      ? selectedName
      : null;
  if (best == null) return null;
  return group.type == 'url-test' ? '当前 $best · 最低延迟' : '当前 $best';
}
