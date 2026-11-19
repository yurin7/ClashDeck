/// 保存配置后要不要顺手重启内核。
///
/// 只有「保存的是当前运行配置」且「内核本来就在跑」时才重启：
/// 其他配置只是写到磁盘，下次切换时才会生效。
bool shouldRestartAfterSave({
  required bool isActiveProfile,
  required bool coreActive,
}) {
  return isActiveProfile && coreActive;
}
