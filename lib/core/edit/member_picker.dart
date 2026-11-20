/// 组成员批量选择的纯逻辑：筛选、全选、反选都只算集合，不碰 UI。
///
/// 放在 core 里是为了能直接单测——面板本身只负责渲染和回调。
library;

import '../model/profile.dart';

/// 候选成员：节点、策略组，或系统策略（DIRECT / REJECT）。
class MemberCandidate {
  const MemberCandidate({
    required this.name,
    this.isGroup = false,
    this.inGroup = false,
    this.isBuiltin = false,
    this.note,
  });

  /// 显示名，同时也是 YAML 里引用的名字。
  final String name;

  /// true = 策略组，false = 节点。
  final bool isGroup;

  /// 已经在组里了：面板里置灰、不参与选择。
  final bool inGroup;

  /// true = 内置出站（DIRECT / REJECT / REJECT-DROP），由内核直接处理。
  final bool isBuiltin;

  /// 附加说明，比如 REJECT-DROP 的「不常用」。
  final String? note;

  @override
  String toString() =>
      'MemberCandidate($name, group=$isGroup, builtin=$isBuiltin, in=$inGroup)';
}

/// 组成员面板顶部「内置」段的候选顺序：常用两个在前，REJECT-DROP 标「不常用」。
const List<String> kMemberBuiltins = <String>[
  ...Profile.systemPolicyTargets,
  'REJECT-DROP',
];

/// 生成组成员候选：节点 → 内置出站 → 其它策略组。
List<MemberCandidate> memberCandidates(
  Profile profile, {
  required String groupName,
  required Iterable<String> members,
}) {
  final inside = <String>{...members};
  return <MemberCandidate>[
    for (final proxy in profile.proxies)
      MemberCandidate(name: proxy.name, inGroup: inside.contains(proxy.name)),
    for (final name in kMemberBuiltins)
      MemberCandidate(
        name: name,
        isBuiltin: true,
        inGroup: inside.contains(name),
        note: name == 'REJECT-DROP' ? '不常用' : null,
      ),
    for (final group in profile.groups)
      if (group.name != groupName)
        MemberCandidate(
          name: group.name,
          isGroup: true,
          inGroup: inside.contains(group.name),
        ),
  ];
}

/// 按关键字筛选候选成员。
///
/// 规则：关键字去首尾空白、忽略大小写做子串匹配；空关键字返回全部
/// （包括已在组内的行——它们要显示成置灰状态，不能直接藏掉）。
List<MemberCandidate> filterMemberCandidates(
  List<MemberCandidate> all,
  String query,
) {
  final keyword = query.trim().toLowerCase();
  if (keyword.isEmpty) return List<MemberCandidate>.of(all);
  return <MemberCandidate>[
    for (final candidate in all)
      if (candidate.name.toLowerCase().contains(keyword)) candidate,
  ];
}

/// 「全选」：把当前筛选结果里**还没加入**的成员加进已选集合。
///
/// 已在组内的成员既不可选也不可取消，会被跳过。
Set<String> selectVisible(
  List<MemberCandidate> all,
  String query,
  Set<String> picked,
) {
  final next = Set<String>.of(picked);
  for (final candidate in filterMemberCandidates(all, query)) {
    if (!candidate.inGroup) next.add(candidate.name);
  }
  return next;
}

/// 「反选」：在当前筛选结果里翻转未加入成员的选中状态。
///
/// 先搜关键字再反选，只影响筛选出来的那些行，不会动到其它筛选结果。
Set<String> invertVisible(
  List<MemberCandidate> all,
  String query,
  Set<String> picked,
) {
  final next = Set<String>.of(picked);
  for (final candidate in filterMemberCandidates(all, query)) {
    if (candidate.inGroup) continue;
    if (!next.remove(candidate.name)) next.add(candidate.name);
  }
  return next;
}

/// 把已选集合裁到「当前仍可加入」的范围内。///
/// 搜索关键字变化时不用调用；它用于成员在面板打开期间被别处改动后的兜底，
/// 避免把已在组内的名字又提交一次。
Set<String> prunePicked(List<MemberCandidate> all, Set<String> picked) {
  final selectable = <String>{
    for (final candidate in all)
      if (!candidate.inGroup) candidate.name,
  };
  return <String>{
    for (final name in picked)
      if (selectable.contains(name)) name,
  };
}

/// 批量加入时按节点列表顺序排序，而不是按面板里的点选顺序。
///
/// 链式代理的 members 顺序就是链路顺序，所以「先点 E 再点 D」不应该变成
/// E→D。这里按 [Profile.proxies] 的索引升序排；不在节点列表里的名字
/// （DIRECT / REJECT / 未知项）保持相对顺序排在最后。重复名去重并保留
/// 第一次出现的位置。
List<String> orderNamesByNodeList(Profile profile, Iterable<String> names) {
  final index = <String, int>{
    for (var i = 0; i < profile.proxies.length; i++) profile.proxies[i].name: i,
  };
  final seen = <String>{};
  final known = <String>[];
  final unknown = <String>[];
  for (final name in names) {
    if (!seen.add(name)) continue;
    if (index.containsKey(name)) {
      known.add(name);
    } else {
      unknown.add(name);
    }
  }
  known.sort((a, b) => index[a]!.compareTo(index[b]!));
  return <String>[...known, ...unknown];
}
