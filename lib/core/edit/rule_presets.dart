/// Loyalsoldier/clash-rules 的常用规则集预设。
///
/// 仓库里 `release/*.txt` 是 rule-provider 的 payload 列表（域名或 CIDR），
/// 社区用法是「一个 rule-provider + 一条 RULE-SET」。这里把最常用的几组列出来，
/// 让用户点一次就能把整套路由规则装进配置。
library;

/// 规则集的原始地址前缀。
const String kLoyalRulesBase =
    'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release';

/// 预设里「走代理组」的占位符：导入时替换成用户选的策略组。
const String kProxyPlaceholder = '@proxy';

/// 一条规则集预设。
class RulePreset {
  const RulePreset({
    required this.id,
    required this.label,
    required this.file,
    required this.behavior,
    required this.defaultTarget,
    this.enabledByDefault = true,
    this.description = '',
  });

  /// rule-provider 的名字，也是默认目标组名。
  final String id;

  /// 界面上显示的名字。
  final String label;

  /// 仓库里的文件名，例如 `reject.txt`。
  final String file;

  /// `domain` 或 `ipcidr`。
  final String behavior;

  /// 默认目标：`REJECT` / `DIRECT` / [kProxyPlaceholder]。
  final String defaultTarget;

  final bool enabledByDefault;
  final String description;

  /// 完整下载地址。
  String get url => '$kLoyalRulesBase/$file';
}

/// 常用的一组（顺序即规则插入顺序，越靠前越先匹配）。
const List<RulePreset> kLoyalRulesPresets = [
  RulePreset(
    id: 'reject',
    label: '广告与跟踪域名',
    file: 'reject.txt',
    behavior: 'domain',
    defaultTarget: 'REJECT',
    description: '拦截广告、统计、跟踪用的域名',
  ),
  RulePreset(
    id: 'proxy',
    label: '代理域名',
    file: 'proxy.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    description: '常见被墙域名，走代理组',
  ),
  RulePreset(
    id: 'direct',
    label: '直连域名',
    file: 'direct.txt',
    behavior: 'domain',
    defaultTarget: 'DIRECT',
    description: '国内常见域名，直接连',
  ),
  RulePreset(
    id: 'private',
    label: '内网 / 本机地址',
    file: 'private.txt',
    behavior: 'domain',
    defaultTarget: 'DIRECT',
    description: '局域网与保留地址，别走代理',
  ),
  RulePreset(
    id: 'gfw',
    label: 'GFW 域名',
    file: 'gfw.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    description: '被墙名单，通常和 proxy 一起用',
  ),
  RulePreset(
    id: 'tld-not-cn',
    label: '非中国 TLD',
    file: 'tld-not-cn.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    enabledByDefault: false,
    description: '所有非 .cn 顶级域，范围很大，按需开启',
  ),
  RulePreset(
    id: 'cncidr',
    label: '国内 IP 段',
    file: 'cncidr.txt',
    behavior: 'ipcidr',
    defaultTarget: 'DIRECT',
    description: '国内 IP，按 IP 直连',
  ),
  RulePreset(
    id: 'lancidr',
    label: '内网 IP 段',
    file: 'lancidr.txt',
    behavior: 'ipcidr',
    defaultTarget: 'DIRECT',
    description: '192.168 / 10. / 172.16 等内网段',
  ),
  RulePreset(
    id: 'telegramcidr',
    label: 'Telegram IP 段',
    file: 'telegramcidr.txt',
    behavior: 'ipcidr',
    defaultTarget: kProxyPlaceholder,
    enabledByDefault: false,
    description: 'Telegram 的 IP 段，想走代理就开',
  ),
];

/// 把预设的默认目标解析成真正的组名。
String presetTargetFor(RulePreset preset, String proxyGroup) {
  final target = preset.defaultTarget;
  if (target != kProxyPlaceholder) return target;
  return proxyGroup.isEmpty ? 'PROXY' : proxyGroup;
}

/// 预设列表里第一个合适的「代理组」名字（没有就回退 `PROXY`）。
String suggestProxyGroup(Iterable<String> groupNames) {
  final names = groupNames.toList(growable: false);
  if (names.contains('PROXY')) return 'PROXY';
  if (names.isNotEmpty) return names.first;
  return 'PROXY';
}
