/// 版本号解析与比较：只关心中间用点分开的 major.minor.patch。
///
/// 约定（与 C24 需求一致）：
/// - 接受可选的 `v` 前缀、`-prerelease` 后缀与 `+build` 元数据，比较时忽略它们；
/// - 任何解析失败都返回 null，让调用方按「版本无效」处理，而不是抛异常。
class SemVer implements Comparable<SemVer> {
  const SemVer(this.major, this.minor, this.patch);

  final int major;
  final int minor;
  final int patch;

  static final RegExp _core = RegExp(r'^(\d+)\.(\d+)\.(\d+)$');

  /// 解析 `0.2.1` / `v0.2.1` / `0.2.1-beta.1+2072`；失败返回 null。
  static SemVer? tryParse(String raw) {
    var text = raw.trim();
    if (text.toLowerCase().startsWith('v')) text = text.substring(1);

    final plus = text.indexOf('+');
    if (plus >= 0) text = text.substring(0, plus);
    final dash = text.indexOf('-');
    if (dash >= 0) text = text.substring(0, dash);

    final match = _core.firstMatch(text);
    if (match == null) return null;
    final major = int.tryParse(match.group(1)!);
    final minor = int.tryParse(match.group(2)!);
    final patch = int.tryParse(match.group(3)!);
    if (major == null || minor == null || patch == null) return null;
    return SemVer(major, minor, patch);
  }

  /// 供 UI 直接显示的规范形式（不含 v / build / prerelease）。
  String get display => '$major.$minor.$patch';

  @override
  int compareTo(SemVer other) {
    if (major != other.major) return major.compareTo(other.major);
    if (minor != other.minor) return minor.compareTo(other.minor);
    return patch.compareTo(other.patch);
  }

  bool operator >(SemVer other) => compareTo(other) > 0;

  bool operator <(SemVer other) => compareTo(other) < 0;

  bool operator >=(SemVer other) => compareTo(other) >= 0;

  @override
  bool operator ==(Object other) =>
      other is SemVer &&
      other.major == major &&
      other.minor == minor &&
      other.patch == patch;

  @override
  int get hashCode => Object.hash(major, minor, patch);

  @override
  String toString() => display;
}

/// 远端版本是否比本机新；任一版本解析失败都返回 false（宁可漏更新，不乱提示）。
bool isNewerVersion(String latest, String current) {
  final remote = SemVer.tryParse(latest);
  final local = SemVer.tryParse(current);
  if (remote == null || local == null) return false;
  return remote > local;
}

/// 自动检查的节流：从未检查过，或距上次检查超过 [interval] 才允许再查。
bool shouldAutoCheck(
  DateTime? lastCheckAt, {
  DateTime? now,
  Duration interval = const Duration(hours: 24),
}) {
  if (lastCheckAt == null) return true;
  final current = now ?? DateTime.now();
  return current.difference(lastCheckAt) >= interval;
}
