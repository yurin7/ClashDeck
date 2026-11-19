/// Pulse 打开时自动补一轮延迟测速的判定。
///
/// 规则（用户 m05724）：
/// - 打开 Pulse 时若还没有任何延迟数据，自动测一轮（内核运行走内核，未运行走 TCP 近似）；
/// - 同一份配置在一次 App 运行期间只自动触发一次；切换到别的配置后，
///   该配置第一次打开 Pulse 时仍可补测一轮；
/// - 正在测速时不重复触发（并且不再排队，避免测完又冒出一轮）。
class PulseAutoDelayGate {
  final Set<String> _judged = <String>{};

  /// 是否已经有过判断（无论是否真的触发）。
  bool get done => _judged.isNotEmpty;

  /// 返回 true 表示调用方应立即发起一轮全节点延迟测速。
  bool shouldTrigger({
    required String? profile,
    required Map<String, int?> delays,
    required bool measuring,
  }) {
    final key = profile ?? '';
    if (!_judged.add(key)) return false;
    if (measuring) return false;
    return !delays.values.any((value) => value != null);
  }
}
