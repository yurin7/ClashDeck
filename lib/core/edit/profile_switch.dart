/// 切换运行配置时，列表里单行的视觉状态。
///
/// 切换要「停内核 → 换配置文件 → 重启内核」，期间列表**保持原有顺序**
/// （不把新配置挪到最前），只用行内状态告诉用户正在发生什么，避免跳变。
enum ProfileRowPhase {
  /// 普通行。
  normal,

  /// 正在切过去的那一行。
  switching,

  /// 当前运行配置，且没有正在切换它。
  active,
}

/// 算出 [fileName] 这一行该显示的状态。
///
/// 「切换中」优先于「运行中」：旧内核已停、新配置还没起来，此时还挂着
/// 「运行中」会和内核实际状态对不上。
ProfileRowPhase profileRowPhase(
  String fileName, {
  required String? activeFileName,
  required String? switchingFileName,
}) {
  if (switchingFileName == fileName) return ProfileRowPhase.switching;
  if (activeFileName == fileName) return ProfileRowPhase.active;
  return ProfileRowPhase.normal;
}
