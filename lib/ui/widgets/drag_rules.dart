/// 拖放接受规则。
///
/// 抽成纯函数是因为这些规则同时被卡片高亮、落点提示和回弹文案依赖，
/// 行为测试（同组/重复/relay）直接断言这里比驱动真实手势更稳。
library;

import '../../core/edit/config_ops.dart';
import '../../core/model/profile.dart';

/// 组卡是否应该接受这次节点拖放。
///
/// - 链式组只接受链内间隙拖拽，整卡一律拒绝；
/// - 拖回源组不产生任何数据变化；
/// - 已在组里的节点不再重复加入。
bool shouldAcceptNodeDrop({
  required String? fromGroup,
  required String targetGroup,
  required bool relay,
  required bool alreadyMember,
}) {
  if (relay) return false;
  if (fromGroup == targetGroup) return false;
  if (alreadyMember) return false;
  return true;
}

/// 这次拖放失败时是否该提示「已在组里」。
bool shouldHintDuplicate({
  required String? fromGroup,
  required String targetGroup,
  required bool alreadyMember,
}) => fromGroup == targetGroup || alreadyMember;

/// 只有可编辑的手动选择组能接收其他策略组。
bool acceptsGroupMembers(GroupEntry group) =>
    group.type == 'select' &&
    !group.computedMembers &&
    group.name != kAutoGroupName &&
    !Profile.builtinTargets.contains(group.name);

/// 跨组移动的是一条引用，落点不能让被引用的组绕回来引用自己。
bool shouldAcceptGroupDrop({
  required Map<String, GroupEntry> groups,
  required String name,
  required String? fromGroup,
  required String targetGroup,
}) {
  final source = groups[fromGroup];
  final target = groups[targetGroup];
  if (source == null ||
      source.computedMembers ||
      source.name == kAutoGroupName ||
      !source.members.contains(name) ||
      !groups.containsKey(name) ||
      target == null ||
      !acceptsGroupMembers(target) ||
      target.name == fromGroup ||
      target.members.contains(name)) {
    return false;
  }

  final pending = [name];
  final visited = <String>{};
  while (pending.isNotEmpty) {
    final member = pending.removeLast();
    if (member == targetGroup) return false;
    if (!visited.add(member)) continue;
    if (groups[member] case final group?) pending.addAll(group.members);
  }
  return true;
}
