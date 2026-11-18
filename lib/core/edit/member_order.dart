import '../model/profile.dart';

/// 组内成员顺序与「当前出口」的纯函数规则。
///
/// 顺序固定为：**代理节点 → 其它成员（策略组等）→ DIRECT → REJECT**。
/// 代理节点按 `proxies:` 的声明顺序排列（与节点列表 UI 一致），其它成员保持
/// 原有相对顺序；内置出站永远排在最后，DIRECT 在 REJECT 之前。
/// mihomo 的 select 组默认取第一个成员作为出口，顺序错了会让默认流量走
/// DIRECT，所以每次增删/排序都要归一化。
List<String> normalizeMemberOrder(
  List<String> members, {
  required List<String> proxyOrder,
}) {
  final proxies = <String>[];
  final others = <String>[];
  final builtins = <String>[];
  final known = proxyOrder.toSet();
  for (final member in members) {
    if (known.contains(member)) {
      proxies.add(member);
    } else if (Profile.builtinTargets.contains(member)) {
      builtins.add(member);
    } else {
      others.add(member);
    }
  }
  final rank = <String, int>{
    for (var i = 0; i < proxyOrder.length; i++) proxyOrder[i]: i,
  };
  proxies.sort((a, b) => rank[a]!.compareTo(rank[b]!));
  final orderedBuiltins = <String>[
    if (builtins.contains('DIRECT')) 'DIRECT',
    if (builtins.contains('REJECT')) 'REJECT',
    for (final builtin in builtins)
      if (builtin != 'DIRECT' && builtin != 'REJECT') builtin,
  ];
  return <String>[...proxies, ...others, ...orderedBuiltins];
}

/// 组内「当前选中成员」的解析：记住的选择仍然存在就用它，否则按规范自动选一个。
///
/// 优先代理节点（`proxies:` 顺序最靠前的那个），没有节点再 DIRECT，再 REJECT；
/// 只有策略组成员时选第一个策略组。空组返回 null。
String? defaultGroupSelection(
  List<String> members, {
  List<String> proxyOrder = const <String>[],
  String? saved,
}) {
  if (saved != null && saved.isNotEmpty && members.contains(saved)) {
    return saved;
  }
  for (final proxy in proxyOrder) {
    if (members.contains(proxy)) return proxy;
  }
  for (final member in members) {
    if (!Profile.builtinTargets.contains(member)) return member;
  }
  if (members.contains('DIRECT')) return 'DIRECT';
  if (members.contains('REJECT')) return 'REJECT';
  return members.isEmpty ? null : members.first;
}
