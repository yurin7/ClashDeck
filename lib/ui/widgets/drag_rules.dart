/// 拖放接受规则。
///
/// 抽成纯函数是因为这些规则同时被卡片高亮、落点提示和回弹文案依赖，
/// 行为测试（同组/重复/relay）直接断言这里比驱动真实手势更稳。
library;

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
