import '../model/profile.dart';
import 'geosite_index.dart';
import 'rule_presets.dart';

/// `RULE-SET` 里的 provider 名 → 预设中文名（查不到返回 null）。
String? presetLabelOf(String providerName) {
  for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets]) {
    if (preset.id == providerName) return preset.label;
  }
  return null;
}

/// `GEOSITE` / `GEOIP` 的 code → 中文名；查不到（或与 code 相同）返回 null。
String? geositeNameOf(String code) {
  final label = geositeLabelOf(code);
  return label == code ? null : label;
}

/// 规则行的主标题：优先给用户能认出的名字。
///
/// 本地规则看匹配内容；在线规则集是 `id · 中文名`；GEO 是 `code · 中文名`；
/// 兜底规则没有匹配内容，统一显示「所有未匹配流量」。
String ruleTitleOf(RuleEntry rule) {
  if (rule.isTerminal) return '所有未匹配流量';
  final payload = rule.payload;
  if (payload.isEmpty) return rule.type;
  if (rule.type == 'RULE-SET') {
    final label = presetLabelOf(payload);
    return label == null ? payload : '$payload · $label';
  }
  if (rule.type == 'GEOSITE' || rule.type == 'GEOIP') {
    final label = geositeNameOf(payload);
    return label == null ? payload : '$payload · $label';
  }
  return payload;
}
