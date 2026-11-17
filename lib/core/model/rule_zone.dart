/// 规则分区：本地精确规则、在线规则集、GEO 数据、以及末尾兜底。
///
/// 分区是**匹配优先级**的可视化：本地精确规则（手写的域名/IP/进程）排在
/// 在线规则集（RULE-SET）与 GEO 数据之前，避免某个大规则集先把指定域名吞掉；
/// GEO 排在 RULE-SET 之后，作为「整包域名之外再补一层」的兜底手段。
library;

/// 规则所属区块。
enum RuleZone {
  /// 手写的精确规则：DOMAIN、DOMAIN-SUFFIX、IP-CIDR、PROCESS-NAME……
  local,

  /// 在线规则集：RULE-SET，按整包匹配远端 provider。
  online,

  /// GEO 数据：GEOSITE / GEOIP，使用配置自带的 geo 库离线命中。
  geo,

  /// 兜底规则：MATCH / FINAL，永远最后。
  terminal,
}

/// 算作「在线」的规则类型（大小写不敏感，均为大写写法）。
const Set<String> kOnlineRuleTypes = {'RULE-SET'};

/// 算作「GEO」的规则类型。
const Set<String> kGeoRuleTypes = {'GEOSITE', 'GEOIP'};

/// 兜底规则类型。
const Set<String> kTerminalZoneTypes = {'MATCH', 'FINAL'};

/// 取一条规则的类型（首个逗号之前的部分，去空白、转大写）。
///
/// 规则行可能带行内注释（`DOMAIN,x,DIRECT # 备注`），类型总在最前面，
/// 所以这里只看第一个逗号之前即可。
String ruleTypeOf(String raw) {
  final line = raw.split('#').first.trim();
  final comma = line.indexOf(',');
  final head = comma < 0 ? line : line.substring(0, comma);
  // 传进来的可能是 YAML 列表项原文（`- GEOSITE,openai,PROXY`），去掉前导短横。
  final bare = head.trim().replaceFirst(RegExp(r'^-\s*'), '');
  return bare.toUpperCase();
}

/// 判断一条规则属于哪个区块。
RuleZone ruleZoneOf(String raw) {
  final type = ruleTypeOf(raw);
  if (kTerminalZoneTypes.contains(type)) return RuleZone.terminal;
  if (kOnlineRuleTypes.contains(type)) return RuleZone.online;
  if (kGeoRuleTypes.contains(type)) return RuleZone.geo;
  return RuleZone.local;
}

/// 这条规则是不是兜底（MATCH / FINAL）。
bool isTerminalRule(String raw) => ruleZoneOf(raw) == RuleZone.terminal;
