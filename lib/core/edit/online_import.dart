/// 在线规则集的导入：先把「会新建 / 会更新 / 会跳过什么」算清楚，
/// 确认之后再按同一份数据落地。
///
/// 之所以把预览和写入都放在 core 里，是为了能脱离 UI 单测：
/// 面板只负责勾选，计数和目标组（一律 [kDefaultGroupName]）由这里决定。
library;

import '../../data/rule_cache.dart';
import '../yaml/yaml_doc.dart';
import 'config_ops.dart';
import 'import_plan.dart';
import 'import_rules.dart';
import 'rule_presets.dart';

/// 一个已经拉取完的在线规则集。
class FetchedPreset {
  const FetchedPreset({required this.preset, this.body, this.text, this.error});

  final RulePreset preset;

  /// 解析后的规则集内容；拉取失败时为 null。
  final RuleProviderBody? body;

  /// 原始正文（classical 规则集保留注释和顺序）。
  final String? text;

  /// 失败原因（拉取 / 解析）。
  final String? error;
}

/// 在线导入的预览结果。
class OnlineImportPlan {
  const OnlineImportPlan({
    required this.plan,
    required this.toApply,
    this.skippedIds = const [],
    this.failedIds = const [],
  });

  /// 给确认弹窗看的计数。
  final ImportPlan plan;

  /// 真正会写进配置的项（拉取成功的项减去内容重复被跳过的项）。
  final List<FetchedPreset> toApply;

  /// 内容与已有规则集完全相同、直接跳过的规则集 id。
  final List<String> skippedIds;

  /// 拉取 / 解析失败、无法导入的规则集 id。
  final List<String> failedIds;
}

/// 一次在线导入的落地结果。
class OnlineImportResult {
  const OnlineImportResult({
    required this.doc,
    this.applied = const [],
    this.failed = const [],
    this.failedPresets = const [],
    this.hints = const [],
    this.providersUpdated = 0,
    this.groupsMade = 0,
    this.rulesRetargeted = 0,
  });

  final YamlDoc doc;

  /// 成功写入的规则集中文名。
  final List<String> applied;

  /// 失败原因（面向用户的一句话）。
  final List<String> failed;

  /// 失败项，用于「重试失败项」。
  final List<RulePreset> failedPresets;

  /// 内核侧提示（behavior 变化、沿用原有定义等）。
  final List<String> hints;

  final int providersUpdated;
  final int groupsMade;
  final int rulesRetargeted;

  bool get isEmpty => applied.isEmpty;
}

/// 算一遍在线导入的计划，不写任何东西。
///
/// [cachedBody] 用于判断「内容完全相同但换了名字」的规则集；传 null 时
/// 只按 provider 名和规范化后的 URL 去重（单测里常用）。
Future<OnlineImportPlan> planOnlineImport(
  YamlDoc doc,
  List<FetchedPreset> items, {
  String target = kDefaultGroupName,
  Future<String?> Function(String id)? cachedBody,
}) async {
  final existing = <String, String>{};
  final raw = doc.plainAt(['rule-providers']);
  if (raw is Map) {
    for (final entry in raw.entries) {
      final value = entry.value;
      existing['${entry.key}'] = value is Map && value['url'] is String
          ? normalizeRuleSetUrl(value['url'] as String)
          : '';
    }
  }

  final newProviders = <String>[];
  final updatedProviders = <String>[];
  final similar = <String, String>{};
  final skippedIds = <String>[];
  final failedIds = <String>[];
  final toApply = <FetchedPreset>[];

  for (final item in items) {
    final id = item.preset.id;
    final body = item.body;
    if (body == null) {
      failedIds.add(id);
      continue;
    }
    final url = normalizeRuleSetUrl(item.preset.url);
    final sameUrl = url.isNotEmpty && existing.values.contains(url);
    if (existing.containsKey(id) || sameUrl) {
      updatedProviders.add(id);
      toApply.add(item);
      continue;
    }
    // 内容相同、名字不同 → 视为同一个规则集，不重复建 provider。
    if (cachedBody != null) {
      final text = item.text == null
          ? ruleCacheBody(body.entries, body.behavior)
          : ruleCacheBodyFromRaw(item.text!, body.behavior);
      var sameAsCached = false;
      for (final other in existing.keys) {
        final cached = await cachedBody(other);
        if (cached != null && cached == text) {
          sameAsCached = true;
          break;
        }
      }
      if (sameAsCached) {
        skippedIds.add(id);
        continue;
      }
    }
    for (final other in existing.keys) {
      if (looksLikeSameName(other, id)) {
        similar[id] = other;
        break;
      }
    }
    newProviders.add(id);
    toApply.add(item);
  }

  return OnlineImportPlan(
    plan: ImportPlan(
      newProviders: newProviders,
      updatedProviders: updatedProviders,
      skippedRules: skippedIds.length,
      rulesToAdd: toApply.length,
      similarNames: similar,
    ),
    toApply: toApply,
    skippedIds: skippedIds,
    failedIds: failedIds,
  );
}

/// 按预览结果落地：`RULE-SET,<id>,<target>`，目标默认 [kDefaultGroupName]。
///
/// [cachePathFor] 返回本地缓存文件路径时，provider 会写成 `type: file`，
/// 内核运行时不再依赖出网（这是之前 EOF 问题的修法）。
OnlineImportResult applyOnlineImport(
  YamlDoc doc,
  OnlineImportPlan plan, {
  String target = kDefaultGroupName,
  String? Function(String id)? cachePathFor,
}) {
  var next = doc;
  final applied = <String>[];
  final failed = <String>[];
  final failedPresets = <RulePreset>[];
  final hints = <String>[];
  var providersUpdated = 0;
  var groupsMade = 0;
  var rulesRetargeted = 0;

  for (final item in plan.toApply) {
    final body = item.body;
    if (body == null) continue;
    try {
      final outcome = importRuleProvider(
        next,
        body: body,
        name: item.preset.id,
        target: target,
        url: item.preset.url,
        filePath: cachePathFor?.call(item.preset.id),
      );
      next = outcome.doc;
      applied.add(item.preset.label);
      providersUpdated += outcome.providersUpdated.length;
      groupsMade += outcome.groupsAdded.length;
      rulesRetargeted += outcome.rulesRetargeted;
      hints.addAll(outcome.warnings);
    } on ConfigEditException catch (e) {
      failed.add('${item.preset.label}（${e.message}）');
      failedPresets.add(item.preset);
    }
  }

  return OnlineImportResult(
    doc: next,
    applied: applied,
    failed: failed,
    failedPresets: failedPresets,
    hints: hints,
    providersUpdated: providersUpdated,
    groupsMade: groupsMade,
    rulesRetargeted: rulesRetargeted,
  );
}
