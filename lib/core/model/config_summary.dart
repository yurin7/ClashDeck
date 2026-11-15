import '../yaml/yaml_doc.dart';
import 'profile.dart';

/// 一份配置的轻量摘要，用于首页卡片快速展示（不做完整校验）。
///
/// 与 [Profile] 一样是只读派生视图：每次 [fromText] 都重新解析文本。
class ConfigSummary {
  const ConfigSummary({
    required this.proxies,
    required this.groups,
    required this.rules,
    required this.mode,
    required this.valid,
    this.error,
  });

  /// 节点数（`proxies:`）。
  final int proxies;

  /// 策略组数（`proxy-groups:`）。
  final int groups;

  /// 规则数（`rules:`）。
  final int rules;

  /// 运行模式（`mode:`），缺省时与 [Profile.mode] 一致为 `rule`；
  /// 解析失败为 null。
  final String? mode;

  /// YAML 能被解析且根节点是映射。
  final bool valid;

  /// 解析失败原因；根节点不是映射时为 null。
  final String? error;

  /// 读不到或解析不了时的占位值。
  static const ConfigSummary unknown = ConfigSummary(
    proxies: 0,
    groups: 0,
    rules: 0,
    mode: null,
    valid: false,
  );

  /// 解析 [text] 并按 [Profile] 的语义计数。
  ///
  /// 非法 YAML 或根节点不是映射时收敛为 `valid: false`，
  /// 绝不向调用方抛异常——首页不能因为某一份坏配置整页报错。
  static ConfigSummary fromText(String text) {
    final doc = YamlDoc.parse(text);
    if (!doc.isValid) {
      return ConfigSummary(
        proxies: 0,
        groups: 0,
        rules: 0,
        mode: null,
        valid: false,
        error: doc.error?.message,
      );
    }
    final profile = Profile.from(doc);
    return ConfigSummary(
      proxies: profile.proxies.length,
      groups: profile.groups.length,
      rules: profile.rules.length,
      mode: profile.mode,
      valid: true,
    );
  }
}
