/// 规则集预设：Loyalsoldier/clash-rules（14 个 txt）+ ACL4SSR 精选 `.list`，
/// 以及 GEOSITE 常用服务（走内核内置的 geosite.dat，不落 rule-provider）。
///
/// rule-provider 的 name 带来源前缀（`loyal-` / `acl-`），避免两套规则集撞名。
library;

/// Loyalsoldier 规则集的原始地址前缀。
const String kLoyalRulesBase =
    'https://raw.githubusercontent.com/Loyalsoldier/clash-rules/release';

/// ACL4SSR 规则集（classical 格式 `.list`）的地址前缀。
const String kAclRulesBase =
    'https://raw.githubusercontent.com/ACL4SSR/ACL4SSR/master/Clash/Ruleset';

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
    this.baseUrl = kLoyalRulesBase,
    this.source = 'Loyalsoldier',
    this.enabledByDefault = true,
    this.enabledInCurated = false,
    this.description = '',
  });

  /// rule-provider 的名字（带 `loyal-` / `acl-` 前缀）。
  final String id;

  /// 界面上显示的名字。
  final String label;

  /// 仓库里的文件名，例如 `reject.txt` / `Apple.list`。
  final String file;

  /// `domain` / `ipcidr` / `classical`。
  final String behavior;

  /// 默认目标：`REJECT` / `DIRECT` / [kProxyPlaceholder]。
  final String defaultTarget;

  /// 下载地址前缀。
  final String baseUrl;

  /// 来源，写在界面上方便分辨。
  final String source;

  /// 打开面板时是否默认勾选（精选页签）。
  final bool enabledByDefault;

  /// 是否归在「精选」页签（否则只在全量/后续 P1 里出现）。
  final bool enabledInCurated;

  final String description;

  /// 完整下载地址。
  String get url => '$baseUrl/$file';
}

/// Loyalsoldier 全量 14 个 txt。
const List<RulePreset> kLoyalRulesPresets = [
  RulePreset(
    id: 'loyal-reject',
    label: '广告与跟踪域名',
    file: 'reject.txt',
    behavior: 'domain',
    defaultTarget: 'REJECT',
    enabledInCurated: true,
    description: '拦截广告、统计、跟踪用的域名',
  ),
  RulePreset(
    id: 'loyal-proxy',
    label: '代理域名',
    file: 'proxy.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    enabledInCurated: true,
    description: '常见被墙域名，走代理组',
  ),
  RulePreset(
    id: 'loyal-direct',
    label: '直连域名',
    file: 'direct.txt',
    behavior: 'domain',
    defaultTarget: 'DIRECT',
    enabledInCurated: true,
    description: '国内常见域名，直接连',
  ),
  RulePreset(
    id: 'loyal-private',
    label: '内网 / 本机地址',
    file: 'private.txt',
    behavior: 'domain',
    defaultTarget: 'DIRECT',
    enabledInCurated: true,
    description: '局域网与保留地址，别走代理',
  ),
  RulePreset(
    id: 'loyal-gfw',
    label: 'GFW 域名',
    file: 'gfw.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    enabledInCurated: true,
    description: '被墙名单，通常和 proxy 一起用',
  ),
  RulePreset(
    id: 'loyal-apple',
    label: '苹果 Apple 域名',
    file: 'apple.txt',
    behavior: 'domain',
    defaultTarget: 'DIRECT',
    enabledByDefault: false,
    enabledInCurated: true,
    description: '苹果服务域名，国内直连一般更快',
  ),
  RulePreset(
    id: 'loyal-google',
    label: '谷歌 Google 域名',
    file: 'google.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    enabledInCurated: true,
    description: '谷歌全系域名（含 Gmail、Drive、地图）',
  ),
  RulePreset(
    id: 'loyal-icloud',
    label: 'iCloud 域名',
    file: 'icloud.txt',
    behavior: 'domain',
    defaultTarget: 'DIRECT',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'iCloud 同步域名，国内直连通常更快',
  ),
  RulePreset(
    id: 'loyal-applications',
    label: '应用商店与更新',
    file: 'applications.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'App Store、Google Play 等下载与更新域名',
  ),
  RulePreset(
    id: 'loyal-greatfire',
    label: 'GFW 实测域名',
    file: 'greatfire.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    enabledInCurated: true,
    description: 'GreatFire 实测被墙的域名，比 gfw 更新更快',
  ),
  RulePreset(
    id: 'loyal-tld-not-cn',
    label: '非中国 TLD',
    file: 'tld-not-cn.txt',
    behavior: 'domain',
    defaultTarget: kProxyPlaceholder,
    enabledByDefault: false,
    enabledInCurated: true,
    description: '所有非 .cn 顶级域，范围很大，按需开启',
  ),
  RulePreset(
    id: 'loyal-cncidr',
    label: '国内 IP 段',
    file: 'cncidr.txt',
    behavior: 'ipcidr',
    defaultTarget: 'DIRECT',
    enabledInCurated: true,
    description: '国内 IP，按 IP 直连',
  ),
  RulePreset(
    id: 'loyal-lancidr',
    label: '内网 IP 段',
    file: 'lancidr.txt',
    behavior: 'ipcidr',
    defaultTarget: 'DIRECT',
    enabledInCurated: true,
    description: '192.168 / 10. / 172.16 等内网段',
  ),
  RulePreset(
    id: 'loyal-telegramcidr',
    label: 'Telegram IP 段',
    file: 'telegramcidr.txt',
    behavior: 'ipcidr',
    defaultTarget: kProxyPlaceholder,
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Telegram 的 IP 段，想走代理就开',
  ),
];

/// ACL4SSR 精选：文件名大小写敏感，必须和仓库里完全一致。
const List<RulePreset> kAclRulesPresets = [
  RulePreset(
    id: 'acl-apple',
    label: '苹果 Apple（细分）',
    file: 'Apple.list',
    behavior: 'classical',
    defaultTarget: 'DIRECT',
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'ACL4SSR 的 Apple 细分规则',
  ),
  RulePreset(
    id: 'acl-microsoft',
    label: '微软 Microsoft',
    file: 'Microsoft.list',
    behavior: 'classical',
    defaultTarget: 'DIRECT',
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: '微软服务域名（含 Windows / Office / 账号）',
  ),
  RulePreset(
    id: 'acl-google',
    label: '谷歌 Google（细分）',
    file: 'Google.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'ACL4SSR 的 Google 细分规则',
  ),
  RulePreset(
    id: 'acl-googlecn',
    label: '谷歌中国可直连',
    file: 'GoogleCN.list',
    behavior: 'classical',
    defaultTarget: 'DIRECT',
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Google 在国内可直接访问的域名',
  ),
  RulePreset(
    id: 'acl-openai',
    label: 'OpenAI / ChatGPT',
    file: 'OpenAi.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'OpenAI 与 ChatGPT 相关域名',
  ),
  RulePreset(
    id: 'acl-claudeai',
    label: 'Anthropic Claude',
    file: 'ClaudeAI.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'Claude / Anthropic 相关域名',
  ),
  RulePreset(
    id: 'acl-ai',
    label: 'AI 站点合集',
    file: 'AI.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: '常见 AI 服务域名（Gemini、Copilot、Perplexity 等）',
  ),
  RulePreset(
    id: 'acl-netflix',
    label: 'Netflix',
    file: 'Netflix.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'Netflix 域名，配合流媒体节点',
  ),
  RulePreset(
    id: 'acl-disneyplus',
    label: 'Disney+',
    file: 'DisneyPlus.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Disney+ 域名',
  ),
  RulePreset(
    id: 'acl-youtube',
    label: 'YouTube',
    file: 'YouTube.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'YouTube 域名',
  ),
  RulePreset(
    id: 'acl-spotify',
    label: 'Spotify',
    file: 'Spotify.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'Spotify 域名',
  ),
  RulePreset(
    id: 'acl-tiktok',
    label: 'TikTok',
    file: 'TikTok.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'TikTok 域名',
  ),
  RulePreset(
    id: 'acl-telegram',
    label: 'Telegram',
    file: 'Telegram.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'Telegram 域名',
  ),
  RulePreset(
    id: 'acl-twitter',
    label: 'Twitter / X',
    file: 'Twitter.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Twitter / X 域名',
  ),
  RulePreset(
    id: 'acl-instagram',
    label: 'Instagram',
    file: 'Instagram.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Instagram 域名',
  ),
  RulePreset(
    id: 'acl-whatsapp',
    label: 'WhatsApp',
    file: 'Whatsapp.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'WhatsApp 域名',
  ),
  RulePreset(
    id: 'acl-steam',
    label: 'Steam',
    file: 'Steam.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Steam 商店与社区',
  ),
  RulePreset(
    id: 'acl-epic',
    label: 'Epic Games',
    file: 'Epic.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Epic 商店与下载',
  ),
  RulePreset(
    id: 'acl-xbox',
    label: 'Xbox',
    file: 'Xbox.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Xbox 与微软游戏服务',
  ),
  RulePreset(
    id: 'acl-github',
    label: 'GitHub',
    file: 'Github.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledInCurated: true,
    description: 'GitHub 域名（clone 慢时可配上直连优化）',
  ),
  RulePreset(
    id: 'acl-reddit',
    label: 'Reddit',
    file: 'Reddit.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Reddit 域名',
  ),
  RulePreset(
    id: 'acl-amazon',
    label: '亚马逊 Amazon',
    file: 'Amazon.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Amazon 商城与 AWS 部分域名',
  ),
  RulePreset(
    id: 'acl-adobe',
    label: 'Adobe',
    file: 'Adobe.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Adobe 账号与 Creative Cloud',
  ),
  RulePreset(
    id: 'acl-onedrive',
    label: 'OneDrive',
    file: 'OneDrive.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'OneDrive 同步域名',
  ),
  RulePreset(
    id: 'acl-bing',
    label: 'Bing',
    file: 'Bing.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'Bing 搜索与 Copilot 入口',
  ),
  RulePreset(
    id: 'acl-proxygfwlist',
    label: 'GFWList 全量',
    file: 'ProxyGFWlist.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'GFWList 全量域名，体积较大',
  ),
  RulePreset(
    id: 'acl-crypto',
    label: '加密货币站点',
    file: 'Crypto.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: '交易所与钱包相关域名',
  ),
  RulePreset(
    id: 'acl-download',
    label: '下载与更新',
    file: 'Download.list',
    behavior: 'classical',
    defaultTarget: kProxyPlaceholder,
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: '常见下载站与软件更新域名',
  ),
  RulePreset(
    id: 'acl-wechat',
    label: '微信 WeChat',
    file: 'Wechat.list',
    behavior: 'classical',
    defaultTarget: 'DIRECT',
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: '微信域名，建议直连',
  ),
  RulePreset(
    id: 'acl-chinanet',
    label: '国内网络合集',
    file: 'ChinaNet.list',
    behavior: 'classical',
    defaultTarget: 'DIRECT',
    baseUrl: kAclRulesBase,
    source: 'ACL4SSR',
    enabledByDefault: false,
    enabledInCurated: true,
    description: 'ACL4SSR 的国内网络合集，建议直连',
  ),
];

/// 一条 GEOSITE 快捷插入项。
///
/// 它不生成 rule-provider：内核自带 geosite.dat，写一条
/// `GEOSITE,<code>,<target>` 就能命中。
class GeositePick {
  const GeositePick({
    required this.code,
    required this.label,
    required this.description,
    this.defaultTarget = kProxyPlaceholder,
    this.enabledByDefault = false,
    this.group = '其他',
  });

  /// geosite.dat 里的官方名字（大小写不敏感）。
  final String code;

  /// 中文名。
  final String label;

  final String description;

  /// `REJECT` / `DIRECT` / [kProxyPlaceholder]。
  final String defaultTarget;

  final bool enabledByDefault;

  /// 界面上用来分组的标签。
  final String group;
}

/// GEOSITE 常用服务。code 都已在 `assets/geo/geosite_index.json` 里核对存在。
const List<GeositePick> kGeositePicks = [
  // 厂商
  GeositePick(
    code: 'microsoft',
    label: '微软 Microsoft',
    description: 'Windows 更新、Office、微软账号',
    enabledByDefault: true,
    group: '厂商',
  ),
  GeositePick(
    code: 'apple',
    label: '苹果 Apple',
    description: 'App Store、iCloud、Apple 服务',
    defaultTarget: 'DIRECT',
    group: '厂商',
  ),
  GeositePick(
    code: 'google',
    label: '谷歌 Google',
    description: '搜索、Gmail、Drive、地图',
    enabledByDefault: true,
    group: '厂商',
  ),
  GeositePick(
    code: 'google-cn',
    label: '谷歌中国',
    description: 'Google 在国内可直连的域名',
    defaultTarget: 'DIRECT',
    group: '厂商',
  ),
  GeositePick(
    code: 'amazon',
    label: '亚马逊 Amazon',
    description: '商城与 AWS 部分域名',
    group: '厂商',
  ),
  GeositePick(
    code: 'adobe',
    label: 'Adobe',
    description: 'Creative Cloud 与账号',
    group: '厂商',
  ),
  GeositePick(
    code: 'onedrive',
    label: 'OneDrive',
    description: '微软网盘同步',
    group: '厂商',
  ),
  GeositePick(
    code: 'bing',
    label: 'Bing',
    description: 'Bing 搜索与 Copilot',
    group: '厂商',
  ),
  GeositePick(
    code: 'github',
    label: 'GitHub',
    description: '代码托管与 raw 加速',
    enabledByDefault: true,
    group: '厂商',
  ),
  GeositePick(
    code: 'cloudflare',
    label: 'Cloudflare',
    description: 'CDN 与 Workers',
    group: '厂商',
  ),
  GeositePick(
    code: 'paypal',
    label: 'PayPal',
    description: '支付与账号',
    group: '厂商',
  ),
  // AI
  GeositePick(
    code: 'openai',
    label: 'OpenAI / ChatGPT',
    description: 'ChatGPT 与 API',
    enabledByDefault: true,
    group: 'AI',
  ),
  GeositePick(
    code: 'anthropic',
    label: 'Anthropic Claude',
    description: 'Claude 与 API',
    enabledByDefault: true,
    group: 'AI',
  ),
  GeositePick(
    code: 'perplexity',
    label: 'Perplexity',
    description: 'AI 搜索',
    group: 'AI',
  ),
  GeositePick(
    code: 'cursor',
    label: 'Cursor',
    description: 'AI 编辑器',
    group: 'AI',
  ),
  GeositePick(
    code: 'huggingface',
    label: 'Hugging Face',
    description: '模型与数据集',
    group: 'AI',
  ),
  GeositePick(
    code: 'midjourney',
    label: 'Midjourney',
    description: 'AI 绘图',
    group: 'AI',
  ),
  GeositePick(
    code: 'category-ai-!cn',
    label: 'AI 站点（境外）',
    description: 'geosite 的 AI 分类合集',
    group: 'AI',
  ),
  // 流媒体
  GeositePick(
    code: 'netflix',
    label: 'Netflix',
    description: '流媒体',
    enabledByDefault: true,
    group: '流媒体',
  ),
  GeositePick(
    code: 'disney',
    label: 'Disney+',
    description: '流媒体',
    group: '流媒体',
  ),
  GeositePick(
    code: 'youtube',
    label: 'YouTube',
    description: '视频',
    enabledByDefault: true,
    group: '流媒体',
  ),
  GeositePick(
    code: 'spotify',
    label: 'Spotify',
    description: '音乐',
    group: '流媒体',
  ),
  GeositePick(
    code: 'tiktok',
    label: 'TikTok',
    description: '短视频',
    group: '流媒体',
  ),
  GeositePick(
    code: 'bilibili',
    label: '哔哩哔哩',
    description: 'B 站',
    defaultTarget: 'DIRECT',
    group: '流媒体',
  ),
  GeositePick(
    code: 'douyin',
    label: '抖音',
    description: '国内短视频',
    defaultTarget: 'DIRECT',
    group: '流媒体',
  ),
  GeositePick(
    code: 'netease',
    label: '网易云音乐',
    description: '音乐',
    defaultTarget: 'DIRECT',
    group: '流媒体',
  ),
  GeositePick(
    code: 'iqiyi',
    label: '爱奇艺',
    description: '国内视频',
    defaultTarget: 'DIRECT',
    group: '流媒体',
  ),
  GeositePick(
    code: 'youku',
    label: '优酷',
    description: '国内视频',
    defaultTarget: 'DIRECT',
    group: '流媒体',
  ),
  // 社交
  GeositePick(
    code: 'telegram',
    label: 'Telegram',
    description: '即时通讯',
    enabledByDefault: true,
    group: '社交',
  ),
  GeositePick(
    code: 'twitter',
    label: 'Twitter / X',
    description: '社交',
    group: '社交',
  ),
  GeositePick(
    code: 'facebook',
    label: 'Facebook',
    description: '社交',
    group: '社交',
  ),
  GeositePick(
    code: 'instagram',
    label: 'Instagram',
    description: '社交',
    group: '社交',
  ),
  GeositePick(
    code: 'whatsapp',
    label: 'WhatsApp',
    description: '即时通讯',
    group: '社交',
  ),
  GeositePick(
    code: 'discord',
    label: 'Discord',
    description: '语音与社区',
    group: '社交',
  ),
  // 游戏
  GeositePick(code: 'steam', label: 'Steam', description: '商店与社区', group: '游戏'),
  GeositePick(
    code: 'epicgames',
    label: 'Epic Games',
    description: '商店与下载',
    group: '游戏',
  ),
  GeositePick(code: 'xbox', label: 'Xbox', description: '微软游戏服务', group: '游戏'),
  GeositePick(
    code: 'playstation',
    label: 'PlayStation',
    description: '索尼游戏服务',
    group: '游戏',
  ),
  GeositePick(
    code: 'nintendo',
    label: '任天堂 Nintendo',
    description: 'Switch 在线服务',
    group: '游戏',
  ),
  // 合集
  GeositePick(
    code: 'category-ads-all',
    label: '广告拦截（全量）',
    description: '一次拦掉常见广告与统计域名',
    defaultTarget: 'REJECT',
    group: '合集',
  ),
  GeositePick(
    code: 'category-media',
    label: '流媒体合集',
    description: 'geosite 的境外流媒体分类',
    group: '合集',
  ),
  GeositePick(
    code: 'category-games',
    label: '游戏平台合集',
    description: 'geosite 的游戏平台分类',
    group: '合集',
  ),
  GeositePick(
    code: 'category-social-media-!cn',
    label: '境外社交合集',
    description: 'geosite 的境外社交分类',
    group: '合集',
  ),
];

/// 把预设的默认目标解析成真正的组名。
String presetTargetFor(RulePreset preset, String proxyGroup) {
  final target = preset.defaultTarget;
  if (target != kProxyPlaceholder) return target;
  return proxyGroup.isEmpty ? 'DEFAULT' : proxyGroup;
}

/// 把 GEOSITE 项的默认目标解析成真正的组名。
String geositeTargetFor(GeositePick pick, String proxyGroup) {
  final target = pick.defaultTarget;
  if (target != kProxyPlaceholder) return target;
  return proxyGroup.isEmpty ? 'DEFAULT' : proxyGroup;
}

/// 预设列表里第一个合适的「代理组」名字（没有就回退 DEFAULT）。
String suggestProxyGroup(Iterable<String> groupNames) {
  final names = groupNames.toList(growable: false);
  if (names.contains('DEFAULT')) return 'DEFAULT';
  if (names.contains('PROXY')) return 'PROXY';
  if (names.isNotEmpty) return names.first;
  return 'DEFAULT';
}

/// 把中文标签清洗成能当策略组名的字符串。
///
/// 标签里常带括号说明（`OpenAI（含 ChatGPT）`）和斜杠（`内网 / 本机地址`），
/// 直接拿来建组会让组名又长又难认；规则里带逗号也会把 YAML 写坏，所以：
/// 去掉括号及其内容 → 斜杠换空格 → 压缩空白 → 限制长度。
String sanitizeGroupName(String raw) {
  var text = raw.replaceAll(RegExp(r'[（(【\[][^）)】\]]*[）)】\]]'), ' ');
  text = text.replaceAll(RegExp(r'[\\/、]'), ' ');
  text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (text.isEmpty) return 'DEFAULT';
  if (text.length <= 24) return text;
  return text.substring(0, 24).trim();
}
