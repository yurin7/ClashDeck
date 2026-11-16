/// 规则类型词表：UI 下拉顺序与导入时的合法性判断共用一份。
library;

/// 常见规则类型（顺序 = 下拉顺序）。
const List<String> kRuleTypes = [
  'DOMAIN',
  'DOMAIN-SUFFIX',
  'DOMAIN-KEYWORD',
  'DOMAIN-REGEX',
  'GEOSITE',
  'GEOIP',
  'IP-CIDR',
  'IP-CIDR6',
  'SRC-IP-CIDR',
  'SRC-GEOIP',
  'DST-PORT',
  'SRC-PORT',
  'PROCESS-NAME',
  'PROCESS-PATH',
  'PROCESS-NAME-REGEX',
  'RULE-SET',
  'NETWORK',
  'IN-TYPE',
  'AND',
  'OR',
  'NOT',
  'MATCH',
];

/// 支持 no-resolve 的规则类型。
const Set<String> kNoResolveTypes = {
  'IP-CIDR',
  'IP-CIDR6',
  'SRC-IP-CIDR',
  'GEOIP',
  'SRC-GEOIP',
};

/// 兜底规则（只有 `类型,目标` 两段）。
const Set<String> kTerminalRuleTypes = {'MATCH', 'FINAL'};

/// 全部合法类型（含 FINAL 这类不在下拉里的写法）。
final Set<String> kAllRuleTypes = {...kRuleTypes, ...kTerminalRuleTypes};

String normalizeRuleType(String raw) => raw.trim().toUpperCase();

bool isKnownRuleType(String raw) =>
    kAllRuleTypes.contains(normalizeRuleType(raw));
