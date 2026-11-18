import 'dart:async';

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';

import '../core/edit/config_ops.dart';
import '../core/edit/import_plan.dart';
import '../core/edit/import_rules.dart';
import '../core/edit/online_import.dart';
import '../core/edit/rule_layout.dart';
import '../core/edit/rule_presets.dart';
import '../core/edit/rule_targets.dart';
import '../core/model/profile.dart';
import '../core/model/rule_zone.dart';
import '../core/model/rule_types.dart';
import '../core/net/fetch_text.dart';
import '../data/rule_cache.dart';
import '../data/app_prefs.dart';
import '../core/yaml/yaml_doc.dart';
import '../runtime/runtime_controller.dart';
import '../state/editor_state.dart';
import 'import_dialogs.dart';
import 'picker_sheet.dart';
import 'rule_edit_dialog.dart';
import 'dropdown.dart';
import 'rules/geo_import_sheet.dart';
import 'rules/online_import_sheet.dart';
import 'rules/rule_row_card.dart';
import 'theme.dart';
import 'widgets.dart';

class RulesTab extends StatefulWidget {
  const RulesTab({super.key, required this.state, this.runtime});

  final RuntimeController? runtime;

  final EditorState state;

  @override
  State<RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends State<RulesTab> {
  EditorState get s => widget.state;

  /// 在线规则集的自动更新设置（默认开、24 小时）。
  bool _autoUpdate = true;
  int _intervalHours = 24;
  bool _autoChecked = false;

  /// 正在批量刷新缓存：期间禁用按钮，避免并发打同一批 URL。
  bool _refreshing = false;

  /// 每个规则集最近一次缓存时间，用来在行里显示「缓存于 …」。
  final Map<String, DateTime?> _cacheTimes = <String, DateTime?>{};

  /// 这次会话里刷新失败的规则集，行尾标「更新失败」。
  final Set<String> _failedProviders = <String>{};

  bool _localOpen = true;
  bool _onlineOpen = true;
  bool _terminalOpen = true;
  bool _geoOpen = true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadRulePrefs());
  }

  String _formatCacheTime(DateTime at) {
    final local = at.toLocal();
    String two(int v) => v.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  void _fail() {
    final msg = s.lastError;
    if (msg == null) return;
    showToast(context, msg);
  }

  /// GEO 面板：勾选或手输 code，批量写 `GEOSITE,<code>,DEFAULT` 到 GEO 区。
  ///
  /// 目标组统一 DEFAULT；插入位置由 `insertRuleLines` 决定（GEO 区末尾，
  /// 也就是 MATCH 之前），已存在的 code 会跳过，所以反复点「添加」是幂等的。
  Future<void> _openGeoImport() async {
    final existing = <String>{
      for (final rule in s.profile.rules)
        if (rule.type == 'GEOSITE') rule.payload,
    };
    final codes = await showGeoImportSheet(context, existingCodes: existing);
    if (codes == null || codes.isEmpty || !mounted) return;
    final target = _resolveTarget(kDefaultGroupName);
    final plan = planGeositeRules(
      codes: codes,
      existingCodes: existing,
      target: target,
    );
    if (plan.rules.isEmpty) {
      _toast(
        plan.invalid.isEmpty
            ? '这些 GEO 词库都已经在配置里了'
            : '这些 code 不合法：${plan.invalid.join('、')}',
      );
      return;
    }
    final RuleImportOutcome outcome;
    try {
      final base = ConfigOps.ensureDefaultGroup(s.doc);
      outcome = insertRuleLines(base, plan.rules, createMissingGroups: false);
    } on ConfigEditException catch (e) {
      _toast(e.message);
      return;
    }
    if (!s.apply((_) => outcome.doc)) {
      _fail();
      return;
    }
    final skipped = plan.skipped.length + outcome.rulesSkipped;
    _toast(
      '已添加 ${outcome.rulesAdded} 条 GEOSITE'
      '${skipped > 0 ? '，跳过 $skipped 条已存在' : ''}（目标 $target）',
    );
  }

  Future<void> _editRule({RuleEntry? initial, int? index}) async {
    final targets = ruleTargetsFor(s.profile, preferred: initial?.target);

    final result = await showAppDialog<Object>(
      context,
      width: dialogWidthOf(context),
      builder: (_) => RuleEditDialog(
        initialType: initial?.type,
        initialPayload: initial?.payload,
        initialTarget: initial?.target,
        initialNoResolve: initial?.noResolve ?? false,
        targets: targets.primary,
        otherBuiltins: targets.otherBuiltins,
        isNew: initial == null,
      ),
    );

    if (result == null) return; // 取消
    if (result == 'delete') {
      if (index == null) return;
      await _confirmDeleteRule(index);
      return;
    }
    final draft = result as RuleDraft;
    final parts = <String>[
      draft.type,
      if (!kTerminalRuleTypes.contains(draft.type)) draft.payload,
      draft.target,
      if (draft.noResolve) 'no-resolve',
      ...?initial?.options.where((o) => o != 'no-resolve'),
    ];
    final rule = parts.where((p) => p.isNotEmpty).join(',');
    // 新规则按分区插到所属区块的第一位（本地精确 / 在线 / 兜底）；
    // 顺带保证 MATCH 永远在最后一条。编辑既有规则时原地改。
    final ok = index == null
        ? s.addRule(rule)
        : s.apply((d) => ConfigOps.updateRule(d, index, rule));
    if (!ok) _fail();
  }

  /// 行尾「⋮ → 删除」的入口。
  Future<void> _confirmDelete(RuleEntry rule) => _confirmDeleteRule(rule.index);

  /// 删除一条规则前的二次确认（编辑对话框里的删除走同一套）。
  Future<void> _confirmDeleteRule(int index) async {
    if (!mounted) return;
    final confirmed = await showAppDialog<bool>(
      context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除这条规则？'),
        content: Text(
          '这条规则会从当前配置里移除，删掉后只能重新添加。',
          style: Theme.of(ctx).textTheme.bodySmall,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed == true && !s.deleteRule(index)) _fail();
  }

  /// 把一条规则改挂到别的策略组：只替换目标，其余 token 原样保留。
  Future<void> _moveRuleToGroup(RuleEntry rule) async {
    final targets = ruleTargetsFor(s.profile, preferred: rule.target).primary;
    final picked = await showPickerSheet<String>(
      context,
      title: '改挂到组',
      subtitle: rule.raw,
      options: [
        for (final name in targets)
          PickerOption(
            name,
            name,
            subtitle: Profile.builtinTargets.contains(name)
                ? '系统策略'
                : s.profile.group(name)?.typeLabel,
            icon: Profile.builtinTargets.contains(name)
                ? Icons.bolt_outlined
                : Icons.account_tree_outlined,
          ),
      ],
      current: rule.target,
    );
    if (picked == null || picked == rule.target || !mounted) return;
    final updated = _ruleString(rule, target: picked);
    if (!s.apply((doc) => ConfigOps.updateRule(doc, rule.index, updated))) {
      _fail();
    }
  }

  /// 用规则原有 token 重新拼出规则行，只替换目标组。
  String _ruleString(RuleEntry rule, {String? target}) {
    final parts = <String>[
      rule.type,
      if (!rule.isTerminal) rule.payload,
      target ?? rule.target,
      if (rule.noResolve) 'no-resolve',
      ...rule.options.where((option) => option != 'no-resolve'),
    ];
    return parts.where((part) => part.isNotEmpty).join(',');
  }

  /// 在线面板：勾选整包规则集，或填一个自定义地址；目标一律 DEFAULT。
  Future<void> _openOnlineImport() async {
    final request = await showOnlineImportSheet(context);
    if (request == null || !mounted) return;
    switch (request) {
      case OnlinePresetRequest():
        await _applyOnlinePresets(request.presets);
      case OnlineCustomUrlRequest():
        await _importRuleProviderFromUrl(
          request.url,
          groupName: kDefaultGroupName,
        );
    }
  }

  /// 在线区头 ⋮ 里的「粘贴导入…」：多行规则 / YAML 片段 / 规则集地址。
  ///
  /// 仍是原来那个对话框，只是入口挪进了菜单，主面板不再摆一个大粘贴框。
  Future<void> _pasteImport() async {
    final input = await showRuleImportDialog(
      context,
      groups: [for (final g in s.profile.groups) g.name],
    );
    if (input == null) return;
    if (input.preset) {
      // 让上一个对话框的退场动画先跑完，否则新路由的入场动画会停在 0。
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await _openOnlineImport();
      return;
    }
    final text = input.text.trim();
    if (text.isEmpty) return;
    if (_urlPattern.hasMatch(text)) {
      await _importRuleProviderFromUrl(
        text,
        groupName: input.group.isEmpty
            ? kDefaultGroupName
            : _resolveTarget(input.group),
      );
      return;
    }
    final RuleImportOutcome outcome;
    try {
      outcome = importRules(s.doc, text);
    } on ConfigEditException catch (e) {
      if (!mounted) return;
      showToast(context, e.message);
      return;
    }
    if (outcome.isEmpty) {
      if (!mounted) return;
      showToast(
        context,
        outcome.warnings.isEmpty
            ? '没有可导入的规则'
            : '没有可导入的规则：${outcome.warnings.first}',
      );
      return;
    }
    if (!s.apply((_) => outcome.doc)) {
      _fail();
      return;
    }
    if (!mounted) return;
    showToast(context, '已导入：${outcome.summary}');
  }

  /// 拉取勾选的规则集 → 预览 → 写入 provider + `RULE-SET,<id>,DEFAULT`。
  ///
  /// [only] 非空表示只重试这些失败项。
  Future<void> _applyOnlinePresets(
    List<RulePreset> presets, {
    List<RulePreset> only = const <RulePreset>[],
  }) async {
    final wanted = only.isEmpty ? presets : only;
    if (wanted.isEmpty) return;
    _cancelled = false;
    _fetchDone = 0;
    _fetchTotal = wanted.length;
    _progress.value = '';
    final fetched = await _withBusy(
      '正在拉取 ${wanted.length} 个规则集…',
      () => _runWithConcurrency([
        for (final preset in wanted) () => _fetchPreset(preset),
      ]),
      progress: _progress,
      cancellable: true,
    );
    if (_cancelled) {
      _toast('已取消导入');
      return;
    }
    // 拉到就落本地缓存：内核自己拉 provider 在部分网络下会 EOF，
    // 所以规则集一律走 file provider，运行时不再依赖出网。
    final cache = await RuleCache.open();
    final target = _resolveTarget(kDefaultGroupName);
    final preview = await planOnlineImport(
      s.doc,
      fetched,
      target: target,
      cachedBody: cache.read,
    );
    if (!await _confirmPlan(preview.plan)) {
      _toast('已取消导入');
      return;
    }
    for (final item in preview.toApply) {
      final body = item.body;
      if (body == null) continue;
      await cache.write(
        item.preset.id,
        item.text == null
            ? ruleCacheBody(body.entries, body.behavior)
            : ruleCacheBodyFromRaw(item.text!, body.behavior),
        sourceUrl: item.preset.url,
      );
    }
    final result = applyOnlineImport(
      s.doc,
      preview,
      target: target,
      cachePathFor: cache.pathFor,
    );
    final failed = <String>[
      for (final item in fetched)
        if (item.body == null) '${item.preset.label}（${item.error ?? '解析失败'}）',
      ...result.failed,
    ];
    final failedPresets = <RulePreset>[
      for (final item in fetched)
        if (item.body == null) item.preset,
      ...result.failedPresets,
    ];
    if (result.isEmpty) {
      _toast(
        '一个都没导入成功：${failed.isEmpty ? '未知原因' : failed.first}',
        action: failedPresets.isEmpty
            ? null
            : SnackBarAction(
                label: '重试失败项',
                onPressed: () =>
                    _applyOnlinePresets(wanted, only: failedPresets),
              ),
      );
      return;
    }
    if (!s.apply((_) => result.doc)) {
      _fail();
      return;
    }
    await _refreshCacheTimes();
    final parts = <String>[
      '${result.applied.length} 个规则集',
      if (result.providersUpdated > 0) '更新 ${result.providersUpdated} 个同名规则集',
      if (result.groupsMade > 0) '新建 ${result.groupsMade} 个节点组',
      if (result.rulesRetargeted > 0) '改写 ${result.rulesRetargeted} 条目标',
      if (preview.skippedIds.isNotEmpty)
        '跳过 ${preview.skippedIds.length} 个内容相同的规则集',
    ];
    final failedHint = failed.isEmpty
        ? ''
        : '，失败 ${failed.length} 项（${failed.first}）';
    final hintsHint = result.hints.isEmpty ? '' : '；${result.hints.first}';
    _toast(
      '成功 ${result.applied.length} 项：${parts.join(' + ')}$failedHint$hintsHint',
      action: failedPresets.isEmpty
          ? null
          : SnackBarAction(
              label: '重试失败项',
              onPressed: () => _applyOnlinePresets(wanted, only: failedPresets),
            ),
    );
  }

  static final RegExp _urlPattern = RegExp(r'^https?://\S+$');

  /// 从规则集地址导入：拉下来 → 猜 behavior → 写 provider + RULE-SET。
  ///
  /// [groupName] 为空时目标组就用规则集自己的名字（direct.txt → direct），
  /// 同名组不存在会新建，存在就直接附加进去。
  Future<void> _importRuleProviderFromUrl(
    String url, {
    String groupName = '',
  }) async {
    String body;
    try {
      body = await _withBusy('正在拉取规则集…', () => fetchText(url));
    } on ConfigEditException catch (e) {
      _toast(e.message);
      return;
    }
    final parsed = parseRuleProviderBody(body, url: url);
    if (parsed == null) {
      _toast('这个地址里没有可识别的规则集（既不是 payload 列表，也不是一行一条的文本）');
      return;
    }

    final name = parsed.name ?? 'rules';
    final target = groupName.isEmpty ? name : groupName;

    final RuleImportOutcome outcome;
    try {
      outcome = importRuleProvider(
        s.doc,
        body: parsed,
        name: name,
        target: target,
        url: url,
      );
    } on ConfigEditException catch (e) {
      _toast(e.message);
      return;
    }
    if (!s.apply((_) => outcome.doc)) {
      _fail();
      return;
    }
    _toast(
      '已导入「$name」：${parsed.count} 条 ${parsed.behavior} 规则，'
      '目标 $target（${outcome.summary}）',
    );
  }

  /// 导入预览确认；返回 true 才继续写入。
  Future<bool> _confirmPlan(ImportPlan plan) async {
    if (plan.isEmpty && plan.similarLines.isEmpty) return true;
    final ok = await showAppDialog<bool>(
      context,
      width: dialogWidthOf(context),
      builder: (ctx) => AlertDialog(
        title: const Text('导入预览'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(plan.summary),
              if (plan.similarLines.isNotEmpty) ...[
                const SizedBox(height: Insets.sm),
                Text('疑似重名（默认复用已有规则集）：${plan.similarLines.join('、')}'),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('导入'),
          ),
        ],
      ),
    );
    return ok == true;
  }

  /// 规则集/GEOSITE 的目标组：没显式选组就落到「默认」组。
  ///
  /// 不再按规则集名字新建同名组——组是用户的组织单位，规则只是指向它。
  String _resolveTarget(String? chosen) {
    final name = (chosen ?? '').trim();
    final groups = s.profile.groups;
    if (name.isNotEmpty && groups.any((g) => g.name == name)) return name;
    // 目标组可能已被删掉：回落到默认组，再退到第一个 select 组，避免写出
    // 内核不认识的 target（会变成 unknown proxy 使整份配置解析失败）。
    if (groups.any((g) => g.name == kDefaultGroupName)) {
      return kDefaultGroupName;
    }
    for (final group in groups) {
      if (group.type == 'select') return group.name;
    }
    return kDefaultGroupName;
  }

  /// 导入时按「取消」后置位，`_runWithConcurrency` 会在下一个任务前停下。
  bool _cancelled = false;
  int _fetchDone = 0;
  int _fetchTotal = 0;

  /// 已拉完多少个，喂给忙碌对话框。
  final ValueNotifier<String> _progress = ValueNotifier<String>("");

  /// 固定并发跑一批任务：一次性 19 个请求会把手机的 DNS/连接池打满。
  Future<List<T>> _runWithConcurrency<T>(
    List<Future<T> Function()> tasks, {
    int max = 4,
  }) async {
    if (tasks.isEmpty) return <T>[];
    final results = List<T?>.filled(tasks.length, null);
    var next = 0;
    Future<void> worker() async {
      while (true) {
        if (_cancelled) return;
        final index = next++;
        if (index >= tasks.length) return;
        results[index] = await tasks[index]();
        _fetchDone += 1;
        _progress.value = '已拉完 $_fetchDone/$_fetchTotal 个';
      }
    }

    await Future.wait([
      for (var i = 0; i < max && i < tasks.length; i++) worker(),
    ]);
    return [for (final item in results) item as T];
  }

  /// 拉一个规则集：内容、原文和失败原因都带回去，由导入计划决定怎么用。
  Future<FetchedPreset> _fetchPreset(RulePreset preset) async {
    try {
      final fetched = await fetchTextWithMirrors(
        preset.url,
        attemptsPerMirror: 1,
      );
      final parsed = parseRuleProviderBody(fetched.text, url: fetched.url);
      if (parsed == null) {
        return FetchedPreset(preset: preset, error: '没识别出规则集内容');
      }
      return FetchedPreset(preset: preset, body: parsed, text: fetched.text);
    } on ConfigEditException catch (e) {
      return FetchedPreset(preset: preset, error: e.message);
    }
  }

  Future<void> _loadRulePrefs() async {
    final prefs = await AppPrefs.load();
    if (!mounted) return;
    setState(() {
      _autoUpdate = prefs.ruleAutoUpdate;
      _intervalHours = prefs.ruleUpdateIntervalHours;
    });
    await _refreshCacheTimes();
    if (!_autoChecked) {
      _autoChecked = true;
      await _maybeAutoRefresh();
    }
  }

  Future<void> _refreshCacheTimes() async {
    final cache = await RuleCache.open();
    final times = <String, DateTime?>{};
    for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets]) {
      times[preset.id] = await cache.fetchedAt(preset.id);
    }
    if (!mounted) return;
    setState(() {
      _cacheTimes
        ..clear()
        ..addAll(times);
    });
  }

  /// 启动时静默刷新：缓存超过 12 小时就后台拉一遍，失败保留旧文件。
  Future<void> _maybeAutoRefresh() async {
    if (!_autoUpdate || _refreshing) return;
    DateTime? latest;
    for (final at in _cacheTimes.values) {
      if (at == null) continue;
      if (latest == null || at.isAfter(latest)) latest = at;
    }
    if (latest == null) return;
    if (DateTime.now().difference(latest) < const Duration(hours: 12)) {
      return;
    }
    final stale = <RulePreset>[
      for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets])
        if (_cacheTimes[preset.id] != null) preset,
    ];
    await _refreshPresets(stale, silent: true);
  }

  Future<void> _setAutoUpdate(bool enabled) async {
    setState(() => _autoUpdate = enabled);
    final prefs = await AppPrefs.load();
    await prefs.setRuleAutoUpdate(enabled);
  }

  Future<void> _setInterval(int hours) async {
    setState(() => _intervalHours = hours);
    final prefs = await AppPrefs.load();
    await prefs.setRuleUpdateIntervalHours(hours);
  }

  /// 重新拉一批规则集并写缓存。只动缓存文件，不动 YAML。
  Future<void> _refreshPresets(
    List<RulePreset> presets, {
    bool silent = false,
  }) async {
    if (presets.isEmpty || _refreshing) return;
    setState(() => _refreshing = true);
    final cache = await RuleCache.open();
    var ok = 0;
    final failed = <String>{};
    _cancelled = false;
    try {
      final fetched = await _runWithConcurrency([
        for (final preset in presets) () => _fetchPreset(preset),
      ]);
      for (final item in fetched) {
        final body = item.body;
        if (body == null) {
          failed.add(item.preset.id);
          continue;
        }
        await cache.write(
          item.preset.id,
          item.text == null
              ? ruleCacheBody(body.entries, body.behavior)
              : ruleCacheBodyFromRaw(item.text!, body.behavior),
          sourceUrl: item.preset.url,
        );
        ok++;
      }
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
    if (!mounted) return;
    setState(() {
      _failedProviders
        ..removeAll([for (final preset in presets) preset.id])
        ..addAll(failed);
    });
    await _refreshCacheTimes();
    if (silent) return;
    if (ok == 0) {
      _toast('全部更新失败：${failed.length} 个规则集拉不下来');
      return;
    }
    _toast(failed.isEmpty ? '已更新 $ok 个规则集' : '成功 $ok 个，失败 ${failed.length} 个');
    if (widget.runtime?.phase == RuntimePhase.running) {
      _toast('规则已更新，重启内核生效');
    }
  }

  List<RulePreset> _onlinePresets() {
    final ids = <String>{
      for (final rule in s.profile.rules)
        if (rule.type == 'RULE-SET') rule.payload,
    };
    return [
      for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets])
        if (ids.contains(preset.id)) preset,
    ];
  }

  RulePreset? _presetOf(String id) {
    for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets]) {
      if (preset.id == id) return preset;
    }
    return null;
  }

  Widget? _cacheTrailing(BuildContext context, RuleEntry rule) {
    if (rule.type != 'RULE-SET') return null;
    final preset = _presetOf(rule.payload);
    if (preset == null) return null;
    final scheme = Theme.of(context).colorScheme;
    if (_failedProviders.contains(preset.id)) {
      return Pill(label: '更新失败', color: scheme.error, dense: true);
    }
    final at = _cacheTimes[preset.id];
    return Text(
      at == null ? '未缓存' : '缓存于 ${_formatCacheTime(at)}',
      style: mono(10, color: scheme.onSurfaceVariant),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 在线规则集的「更新」入口，从行尾按钮挪进了 ⋮ 菜单。
  VoidCallback? _refreshFor(RuleEntry rule) {
    if (rule.type != 'RULE-SET') return null;
    final preset = _presetOf(rule.payload);
    if (preset == null) return null;
    return () {
      if (_refreshing) return;
      _refreshPresets([preset]);
    };
  }

  String get _intervalLabel =>
      _intervalHours == 168 ? '7 天' : '${_intervalHours}h';

  /// 折叠时区头右侧显示的摘要，比如「自动更新 · 24h」。
  String get _onlineSummary => _autoUpdate ? '自动更新 · $_intervalLabel' : '自动更新关';

  Widget _onlineToolbar(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final empty = _onlinePresets().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: Insets.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Text('自动更新', style: hintStyle(context)),
          SizedBox(
            height: 32,
            child: FittedBox(
              child: Switch(
                value: _autoUpdate,
                onChanged: _refreshing ? null : (v) => _setAutoUpdate(v),
              ),
            ),
          ),
          const Spacer(),
          Text('间隔', style: hintStyle(context)),
          const SizedBox(width: Insets.xs),
          SizedBox(
            width: 104,
            child: AppDropdown<String>(
              value: '$_intervalHours',
              compact: true,
              expand: true,
              enabled: !_refreshing,
              options: const [
                DropdownOption('12', '12h'),
                DropdownOption('24', '24h'),
                DropdownOption('168', '7 天'),
              ],
              onChanged: (value) => _setInterval(int.parse(value)),
            ),
          ),
          const SizedBox(width: Insets.xs),
          OutlinedButton.icon(
            onPressed: (_refreshing || empty)
                ? null
                : () => _refreshPresets(_onlinePresets()),
            icon: const Icon(Icons.cloud_sync_outlined, size: 18),
            label: Text(_refreshing ? '更新中…' : '全部更新'),
            style: OutlinedButton.styleFrom(
              foregroundColor: scheme.primary,
              visualDensity: VisualDensity.compact,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRuleList(
    BuildContext context, {
    required List<RuleEntry> local,
    required List<RuleEntry> online,
    required List<RuleEntry> geo,
    required List<RuleEntry> terminal,
    required bool terminalLate,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return CustomScrollView(
      slivers: [
        SliverPersistentHeader(
          pinned: true,
          delegate: _ZoneHeaderDelegate(
            background: scheme.surface,
            child: _buildZoneHeader(
              context,
              title: '本地精确规则',
              subtitle: '手写的域名 / IP / 进程规则，先于在线规则集匹配',
              rules: local,
              zone: RuleZone.local,
              open: _localOpen,
              onToggle: () => setState(() => _localOpen = !_localOpen),
              onAdd: () => _editRule(),
            ),
          ),
        ),
        if (_localOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              subtitle: '手写的域名 / IP / 进程规则，先于在线规则集匹配',
              rules: local,
              zone: RuleZone.local,
              onlineOpen: false,
              terminalLate: terminalLate,
            ),
          ),
        SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _ZoneHeaderDelegate(
            background: scheme.surface,
            child: _buildZoneHeader(
              context,
              title: '在线规则集',
              subtitle: '按整包匹配，排在本地规则之后',
              rules: online,
              zone: RuleZone.online,
              open: _onlineOpen,
              onToggle: () => setState(() => _onlineOpen = !_onlineOpen),
              onAdd: _openOnlineImport,
              menu: PopupMenuButton<String>(
                tooltip: '更多操作',
                icon: const Icon(Icons.more_vert, size: 18),
                onSelected: (_) => _pasteImport(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'paste', child: Text('粘贴导入…')),
                ],
              ),
            ),
          ),
        ),
        if (_onlineOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              subtitle: '按整包匹配，排在本地规则之后',
              rules: online,
              zone: RuleZone.online,
              onlineOpen: true,
              terminalLate: terminalLate,
            ),
          ),
        SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _ZoneHeaderDelegate(
            background: scheme.surface,
            child: _buildZoneHeader(
              context,
              title: 'GEO 数据',
              subtitle: 'GEOSITE / GEOIP，离线命中，排在规则集之后',
              rules: geo,
              zone: RuleZone.geo,
              open: _geoOpen,
              onToggle: () => setState(() => _geoOpen = !_geoOpen),
              onAdd: _openGeoImport,
            ),
          ),
        ),
        if (_geoOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              subtitle: 'GEOSITE / GEOIP，离线命中，排在规则集之后',
              rules: geo,
              zone: RuleZone.geo,
              onlineOpen: false,
              terminalLate: terminalLate,
            ),
          ),
        SliverToBoxAdapter(
          child: Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        ),
        SliverPersistentHeader(
          pinned: true,
          delegate: _ZoneHeaderDelegate(
            background: scheme.surface,
            child: _buildZoneHeader(
              context,
              title: '兜底规则',
              subtitle: 'MATCH / FINAL，必须在最后',
              rules: terminal,
              zone: RuleZone.terminal,
              open: _terminalOpen,
              onToggle: () => setState(() => _terminalOpen = !_terminalOpen),
            ),
          ),
        ),
        if (_terminalOpen)
          SliverToBoxAdapter(
            child: _buildZoneBody(
              context,
              subtitle: 'MATCH / FINAL，必须在最后',
              rules: terminal,
              zone: RuleZone.terminal,
              onlineOpen: false,
              terminalLate: terminalLate,
            ),
          ),
      ],
    );
  }

  Widget _buildZoneHeader(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<RuleEntry> rules,
    required RuleZone zone,
    required bool open,
    required VoidCallback onToggle,
    VoidCallback? onAdd,
    Widget? menu,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (zone) {
      RuleZone.local => scheme.primary,
      RuleZone.online => scheme.tertiary,
      RuleZone.geo => scheme.secondary,
      RuleZone.terminal => scheme.error,
    };
    return InkWell(
      onTap: onToggle,
      child: Row(
        children: [
          Icon(
            open ? Icons.expand_more : Icons.chevron_right,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          const SizedBox(width: Insets.xs),
          Container(
            width: 3,
            height: 14,
            margin: const EdgeInsets.only(right: Insets.xs),
            decoration: BoxDecoration(
              color: accent,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Expanded(
            child: Text(
              title,
              style: monoStyle(
                context,
                size: 12,
              ).copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (zone == RuleZone.online && !open)
            Padding(
              padding: const EdgeInsets.only(right: Insets.xs),
              child: Text(_onlineSummary, style: hintStyle(context)),
            ),
          ?menu,
          if (onAdd != null)
            IconButton(
              onPressed: onAdd,
              tooltip: '添加…',
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.add, size: 20),
            ),
          Pill(label: '${rules.length} 条', dense: true),
        ],
      ),
    );
  }

  Widget _buildZoneBody(
    BuildContext context, {
    required String subtitle,
    required List<RuleEntry> rules,
    required RuleZone zone,
    required bool onlineOpen,
    bool terminalLate = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.lg, Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(subtitle, style: hintStyle(context)),
          if (zone == RuleZone.online && onlineOpen) ...[
            const SizedBox(height: Insets.sm),
            _onlineToolbar(context),
            if (terminalLate) ...[
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: scheme.error),
                  const SizedBox(width: Insets.xs),
                  Expanded(
                    child: Text(
                      '检测到 MATCH 不在末尾，内核会先命中它后面的规则',
                      style: hintStyle(context)?.copyWith(color: scheme.error),
                    ),
                  ),
                ],
              ),
            ],
          ],
          const SizedBox(height: Insets.xs),
          if (rules.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: Insets.sm),
              child: Text('暂无规则 —— 点右上角「+」添加', style: hintStyle(context)),
            )
          else
            ReorderableListView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              buildDefaultDragHandles: false,
              itemCount: rules.length,
              onReorderItem: (oldIndex, newIndex) {
                if (oldIndex == newIndex) return;
                final from = rules[oldIndex].index;
                final to = rules[newIndex].index;
                if (!s.moveRule(from, to)) _fail();
              },
              itemBuilder: (context, i) {
                final rule = rules[i];
                return Padding(
                  key: ValueKey('rule-${rule.index}'),
                  padding: const EdgeInsets.only(bottom: Insets.sm),
                  child: RuleRowCard(
                    rule: rule,
                    trailing: _cacheTrailing(context, rule),
                    onRefresh: _refreshFor(rule),
                    dragHandle: ReorderableDragStartListener(
                      index: i,
                      child: MouseRegion(
                        cursor: SystemMouseCursors.grab,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Insets.xs,
                            vertical: Insets.xs,
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.drag_indicator,
                                size: 17,
                                color: scheme.onSurfaceVariant.withValues(
                                  alpha: 0.7,
                                ),
                              ),
                              Text(
                                '${i + 1}',
                                style: monoStyle(context, size: 10),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    onTap: () => _editRule(initial: rule, index: rule.index),
                    onEdit: () => _editRule(initial: rule, index: rule.index),
                    onMoveToGroup: () => _moveRuleToGroup(rule),
                    onDelete: () => _confirmDelete(rule),
                  ),
                );
              },
            ),
        ],
      ),
    );
  }

  void _toast(String message, {SnackBarAction? action}) {
    if (!mounted) return;
    showToast(
      context,
      message,
      // 带动作的多留一会儿，够用户点「重试失败项」。
      duration: Duration(milliseconds: action == null ? 2600 : 8000),
      actionLabel: action?.label,
      onAction: action?.onPressed,
    );
  }

  /// 跑一个异步任务，期间盖一层「正在…」的对话框。
  Future<T> _withBusy<T>(
    String message,
    Future<T> Function() task, {
    ValueListenable<String>? progress,
    bool cancellable = false,
  }) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var closed = false;
    unawaited(
      showAppDialog<void>(
        context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: ValueListenableBuilder<String>(
            valueListenable: progress ?? ValueNotifier<String>(""),
            builder: (context, extra, _) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: Insets.md),
                    Expanded(child: Text(message)),
                  ],
                ),
                if (extra.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: Insets.sm),
                    child: Text(extra, style: hintStyle(context)),
                  ),
              ],
            ),
          ),
          actions: [
            if (cancellable)
              TextButton(
                onPressed: () {
                  _cancelled = true;
                  navigator.pop();
                },
                child: const Text('取消'),
              ),
          ],
        ),
      ).then((_) => closed = true),
    );
    try {
      return await task();
    } finally {
      if (!closed) navigator.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final rules = s.profile.rules;
    final scheme = Theme.of(context).colorScheme;
    final local = <RuleEntry>[];
    final online = <RuleEntry>[];
    final geo = <RuleEntry>[];
    final terminal = <RuleEntry>[];
    for (final rule in rules) {
      switch (ruleZoneOf(rule.raw)) {
        case RuleZone.local:
          local.add(rule);
        case RuleZone.online:
          online.add(rule);
        case RuleZone.geo:
          geo.add(rule);
        case RuleZone.terminal:
          terminal.add(rule);
      }
    }
    final terminalLate = RuleLayout.hasTerminalNotLast(s.doc.text);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.sm,
            Insets.lg,
            Insets.xs,
          ),
          child: Row(
            children: [
              Icon(Icons.rule_folder_outlined, size: 18, color: scheme.primary),
              const SizedBox(width: Insets.sm),
              Expanded(
                child: Text(
                  '拖动右侧手柄排序，点击一行编辑；MATCH 必须在最后',
                  style: hintStyle(context),
                ),
              ),
              Pill(label: '${rules.length} 条', dense: true),
            ],
          ),
        ),
        Expanded(
          child: rules.isEmpty
              ? EmptyHint(
                  icon: Icons.rule_outlined,
                  title: '还没有规则',
                  message: '内核按从上到下的顺序匹配，最后用一条 MATCH 兜底。',
                  compact: true,
                )
              : _buildRuleList(
                  context,
                  local: local,
                  online: online,
                  geo: geo,
                  terminal: terminal,
                  terminalLate: terminalLate,
                ),
        ),
      ],
    );
  }
}

class _ZoneHeaderDelegate extends SliverPersistentHeaderDelegate {
  const _ZoneHeaderDelegate({required this.child, required this.background});

  final Widget child;
  final Color background;

  @override
  double get minExtent => 46;

  @override
  double get maxExtent => 46;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    // 吸顶头高度由 delegate 固定，子级必须撑满，否则 SliverGeometry 的
    // layoutExtent 会大于 paintExtent 而触发断言。
    return Material(
      color: background,
      child: SizedBox(
        height: maxExtent,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
          child: Align(alignment: Alignment.centerLeft, child: child),
        ),
      ),
    );
  }

  @override
  bool shouldRebuild(_ZoneHeaderDelegate oldDelegate) =>
      !identical(oldDelegate.child, child) ||
      oldDelegate.background != background;
}
