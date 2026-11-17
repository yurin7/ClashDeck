import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';
import 'package:flutter/foundation.dart';

import '../core/edit/config_ops.dart';
import '../core/edit/geosite_index.dart';
import '../core/edit/import_rules.dart';
import '../core/edit/rule_layout.dart';
import '../core/edit/rule_presets.dart';
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
import 'rule_edit_dialog.dart';
import 'dropdown.dart';
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

  Future<void> _editRule({RuleEntry? initial, int? index}) async {
    final profile = s.profile;
    final targets = <String>{
      ...profile.allTargets,
      if (initial != null) initial.target,
    }.toList();

    final result = await showAppDialog<Object>(
      context,
      builder: (_) => RuleEditDialog(
        initialType: initial?.type,
        initialPayload: initial?.payload,
        initialTarget: initial?.target,
        initialNoResolve: initial?.noResolve ?? false,
        targets: targets,
        isNew: initial == null,
      ),
    );

    if (result == null) return; // 取消
    if (result == 'delete') {
      if (index == null) return;
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

  /// 导入规则：
  /// - 单行 URL → 当成 rule-provider 规则集（Loyalsoldier/clash-rules 那种）；
  /// - 其余 → 纯规则行，或带 proxy-groups / provider 的配置片段。
  Future<void> _importRules() async {
    final input = await showRuleImportDialog(
      context,
      groups: [for (final g in s.profile.groups) g.name],
    );
    if (input == null) return;
    if (input.preset) {
      // 让上一个对话框的退场动画先跑完，否则新路由的入场动画会停在 0。
      await Future<void>.delayed(const Duration(milliseconds: 280));
      await _importLoyalPreset();
      return;
    }
    if (input.text.trim().isEmpty) return;
    final trimmed = input.text.trim();

    if (_urlPattern.hasMatch(trimmed)) {
      await _importRuleProviderFromUrl(trimmed, groupName: input.group);
      return;
    }

    final RuleImportOutcome outcome;
    try {
      outcome = importRules(s.doc, input.text);
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

  /// 一键导入常用规则集：Loyalsoldier / ACL4SSR 走 rule-provider，
  /// GEOSITE 直接写进 rules（离线命中）。
  Future<void> _importLoyalPreset() async {
    final groupNames = [for (final g in s.profile.groups) g.name];
    final choice = await showAppDialog<_PresetChoice>(
      context,
      builder: (_) => _RulePresetSheet(
        proxyGroup: suggestProxyGroup(groupNames),
        groupNames: groupNames,
      ),
    );
    if (choice == null) return;
    if (choice.presets.isEmpty && choice.geosites.isEmpty) return;
    await _applyPresetChoice(choice);
  }

  /// 落地一次导入。`only` 非空时 = 只重试这些规则集（GEOSITE 不重复写）。
  Future<void> _applyPresetChoice(
    _PresetChoice choice, {
    List<RulePreset> only = const <RulePreset>[],
  }) async {
    final presets = only.isEmpty ? choice.presets : only;
    var doc = s.doc;
    final applied = <String>[];
    final failed = <String>[];
    final failedPresets = <RulePreset>[];
    final hints = <String>[];
    final allProxies = [for (final p in s.profile.proxies) p.name];
    var updated = 0;
    var groupsMade = 0;
    var groupsReused = 0;
    var retargeted = 0;

    if (presets.isNotEmpty) {
      _cancelled = false;
      _fetchDone = 0;
      _fetchTotal = presets.length;
      _progress.value = "";
      final fetched = await _withBusy(
        '正在拉取 ${presets.length} 个规则集…',
        () => _runWithConcurrency([
          for (final preset in presets) () => _fetchPreset(preset),
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
      for (final item in fetched) {
        final body = item.body;
        if (body == null) {
          failed.add('${item.preset.label}（${item.error ?? '解析失败'}）');
          failedPresets.add(item.preset);
          continue;
        }
        await cache.write(
          item.preset.id,
          item.text == null
              ? ruleCacheBody(body.entries, body.behavior)
              : ruleCacheBodyFromRaw(item.text!, body.behavior),
          sourceUrl: item.preset.url,
        );
        final groupName = choice.groupFor(item.preset);
        try {
          final outcome = importRuleProvider(
            doc,
            body: body,
            name: item.preset.id,
            // 目标直接指向这个规则集自己的组：内核按 first-match 走，
            // 目标写固定代理组会让「同名组」形同虚设。
            target: groupName,
            url: item.preset.url,
            filePath: cache.pathFor(item.preset.id),
            groupName: groupName,
            groupMembers: allProxies,
          );
          doc = outcome.doc;
          applied.add(item.preset.label);
          updated += outcome.providersUpdated.length;
          groupsMade += outcome.groupsAdded.length;
          groupsReused += outcome.groupsMerged.length;
          retargeted += outcome.rulesRetargeted;
          hints.addAll(outcome.warnings);
        } on ConfigEditException catch (e) {
          failed.add('${item.preset.label}（${e.message}）');
          failedPresets.add(item.preset);
        }
      }
    }

    var geoAdded = 0;
    if (only.isEmpty && choice.geosites.isNotEmpty) {
      // 一次最多 50 条，免得一口气把规则列表撑得太长。
      final lines = [
        for (final pick in choice.geosites.take(50))
          'GEOSITE,${pick.code},${geositeTargetFor(pick, choice.proxyGroup)}',
      ];
      try {
        final outcome = insertRuleLines(doc, lines);
        doc = outcome.doc;
        geoAdded = outcome.rulesAdded;
        hints.addAll(outcome.warnings);
      } on ConfigEditException catch (e) {
        failed.add('GEOSITE（${e.message}）');
      }
    }

    if (applied.isEmpty && geoAdded == 0) {
      _toast(
        '一个都没导入成功：${failed.isEmpty ? '未知原因' : failed.first}',
        action: failedPresets.isEmpty
            ? null
            : SnackBarAction(
                label: '重试失败项',
                onPressed: () =>
                    _applyPresetChoice(choice, only: failedPresets),
              ),
      );
      return;
    }
    if (!s.apply((_) => doc)) {
      _fail();
      return;
    }
    final parts = <String>[
      if (applied.isNotEmpty) '${applied.length} 组规则集',
      if (geoAdded > 0) 'GEOSITE $geoAdded 条',
      if (groupsMade > 0) '新建 $groupsMade 个节点组',
      if (groupsReused > 0) '复用 $groupsReused 个同名组',
      if (retargeted > 0) '改写 $retargeted 条目标',
      if (updated > 0) '更新 $updated 个同名规则集',
    ];
    final failedHint = failed.isEmpty
        ? ''
        : '，失败 ${failed.length} 项（${failed.first}）';
    final hintsHint = hints.isEmpty ? '' : '；${hints.first}';
    _toast(
      '成功 ${applied.length + geoAdded} 项：${parts.join(' + ')}$failedHint$hintsHint',
      action: failedPresets.isEmpty
          ? null
          : SnackBarAction(
              label: '重试失败项',
              onPressed: () => _applyPresetChoice(choice, only: failedPresets),
            ),
    );
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

  Future<_PresetFetch> _fetchPreset(RulePreset preset) async {
    try {
      final fetched = await fetchTextWithMirrors(
        preset.url,
        attemptsPerMirror: 1,
      );
      final parsed = parseRuleProviderBody(fetched.text, url: fetched.url);
      if (parsed == null) {
        return _PresetFetch(preset, error: '没识别出规则集内容', url: fetched.url);
      }
      return _PresetFetch(
        preset,
        body: parsed,
        url: fetched.url,
        text: fetched.text,
      );
    } on ConfigEditException catch (e) {
      return _PresetFetch(preset, error: e.message);
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

  Widget? _rowTrailing(BuildContext context, RuleEntry rule) {
    if (rule.type != 'RULE-SET') return null;
    final preset = _presetOf(rule.payload);
    if (preset == null) return null;
    final scheme = Theme.of(context).colorScheme;
    final at = _cacheTimes[preset.id];
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (_failedProviders.contains(preset.id))
          Pill(label: '更新失败', color: scheme.error, dense: true)
        else
          Text(
            at == null ? '未缓存' : '缓存于 ${_formatCacheTime(at)}',
            style: hintStyle(context),
          ),
        IconButton(
          tooltip: '更新这个规则集',
          visualDensity: VisualDensity.compact,
          onPressed: _refreshing ? null : () => _refreshPresets([preset]),
          icon: const Icon(Icons.refresh, size: 18),
        ),
      ],
    );
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
          const SizedBox(width: Insets.sm),
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
    required List<RuleEntry> terminal,
    required bool terminalLate,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.xs,
        Insets.lg,
        Insets.md,
      ),
      children: [
        _buildZone(
          context,
          title: '本地精确规则',
          subtitle: '手写的域名 / IP / 进程规则，先于在线规则集匹配',
          rules: local,
          zone: RuleZone.local,
          open: _localOpen,
          onToggle: () => setState(() => _localOpen = !_localOpen),
        ),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        const SizedBox(height: Insets.sm),
        _buildZone(
          context,
          title: '在线规则集',
          subtitle: '按整包匹配，排在本地规则之后',
          rules: online,
          zone: RuleZone.online,
          open: _onlineOpen,
          onToggle: () => setState(() => _onlineOpen = !_onlineOpen),
          terminalLate: terminalLate,
        ),
        Divider(height: 1, thickness: 1, color: scheme.outlineVariant),
        const SizedBox(height: Insets.sm),
        _buildZone(
          context,
          title: '兜底规则',
          subtitle: 'MATCH / FINAL，必须在最后',
          rules: terminal,
          zone: RuleZone.terminal,
          open: _terminalOpen,
          onToggle: () => setState(() => _terminalOpen = !_terminalOpen),
        ),
      ],
    );
  }

  Widget _buildZone(
    BuildContext context, {
    required String title,
    required String subtitle,
    required List<RuleEntry> rules,
    required RuleZone zone,
    required bool open,
    required VoidCallback onToggle,
    bool terminalLate = false,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: onToggle,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                vertical: Insets.xs,
                horizontal: Insets.xs,
              ),
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
                      color: zone == RuleZone.local
                          ? scheme.primary
                          : zone == RuleZone.online
                          ? scheme.tertiary
                          : scheme.error,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: monoStyle(
                            context,
                            size: 12,
                          ).copyWith(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 1),
                        Text(subtitle, style: hintStyle(context)),
                      ],
                    ),
                  ),
                  if (zone == RuleZone.online && !open)
                    Padding(
                      padding: const EdgeInsets.only(right: Insets.xs),
                      child: Text(_onlineSummary, style: hintStyle(context)),
                    ),
                  Pill(label: '${rules.length} 条', dense: true),
                ],
              ),
            ),
          ),
          if (zone == RuleZone.online && open) ...[
            _onlineToolbar(context),
            if (terminalLate)
              Padding(
                padding: const EdgeInsets.only(top: Insets.xs),
                child: Row(
                  children: [
                    Icon(Icons.info_outline, size: 14, color: scheme.error),
                    const SizedBox(width: Insets.xs),
                    Expanded(
                      child: Text(
                        '检测到 MATCH 不在末尾，内核会先命中它后面的规则',
                        style: hintStyle(context),
                      ),
                    ),
                  ],
                ),
              ),
          ],
          if (open) ...[
            const SizedBox(height: Insets.xs),
            if (rules.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: Insets.sm),
                child: Text(
                  '暂无规则 —— 用下方「添加规则」或「导入规则」',
                  style: hintStyle(context),
                ),
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
                    child: _RuleRow(
                      rule: rule,
                      trailing: _rowTrailing(context, rule),
                      dragHandle: ReorderableDragStartListener(
                        index: i,
                        child: MouseRegion(
                          cursor: SystemMouseCursors.grab,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: Insets.xs,
                              vertical: Insets.sm,
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
                    ),
                  );
                },
              ),
          ],
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
    final terminal = <RuleEntry>[];
    for (final rule in rules) {
      switch (ruleZoneOf(rule.raw)) {
        case RuleZone.local:
          local.add(rule);
        case RuleZone.online:
          online.add(rule);
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
                  '拖动左侧手柄排序，点击一行编辑；MATCH 必须在最后',
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
                  terminal: terminal,
                  terminalLate: terminalLate,
                ),
        ),
        SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.xs,
              Insets.lg,
              Insets.md,
            ),
            child: Row(
              children: [
                Expanded(
                  child: FilledButton.tonalIcon(
                    onPressed: () => _editRule(),
                    icon: const Icon(Icons.add, size: 20),
                    label: const Text('添加规则'),
                  ),
                ),
                const SizedBox(width: Insets.sm),
                OutlinedButton.icon(
                  onPressed: _importRules,
                  icon: const Icon(Icons.file_download_outlined, size: 20),
                  label: const Text('导入规则'),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 一行规则：拖手柄 | 类型 + 匹配内容 → 目标。
/// `RULE-SET` 里的 provider 名 → 预设中文名（查不到返回 null）。
String? _presetLabelOf(String providerName) {
  for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets]) {
    if (preset.id == providerName) return preset.label;
  }
  return null;
}

/// 规则行第二行展示的匹配内容：`GEOSITE` / `RULE-SET` 顺带把中文名带出来。
String _rulePayloadLabel(RuleEntry rule) {
  if (rule.isTerminal) return '所有未匹配流量';
  final payload = rule.payload;
  if (payload.isEmpty) return payload;
  if (rule.type == 'GEOSITE') {
    final label = geositeLabelOf(payload);
    return label == payload ? payload : '$payload  ·  $label';
  }
  if (rule.type == 'RULE-SET') {
    final label = _presetLabelOf(payload);
    return label == null ? payload : '$payload  ·  $label';
  }
  return payload;
}

class _RuleRow extends StatelessWidget {
  const _RuleRow({
    required this.rule,

    required this.dragHandle,
    required this.onTap,
    this.trailing,
  });

  final RuleEntry rule;

  final Widget dragHandle;
  final VoidCallback onTap;

  /// 行尾附加信息（在线规则集的来源 / 缓存时间 / 更新按钮）。
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final terminal = rule.isTerminal;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          children: [
            Row(
              children: [
                dragHandle,
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                rule.type,
                                style: mono(
                                  12.5,
                                  weight: 700,
                                  letterSpacing: 0.3,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (terminal) ...[
                              const SizedBox(width: Insets.sm),
                              Pill(
                                label: '兜底',
                                color: context.semantic.warn,
                                icon: Icons.flag_outlined,
                                dense: true,
                              ),
                            ],
                            if (rule.noResolve) ...[
                              const SizedBox(width: Insets.xs),
                              const Pill(label: 'no-resolve', dense: true),
                            ],
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                _rulePayloadLabel(rule),
                                style: mono(12, color: scheme.onSurfaceVariant),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Icon(
                              Icons.arrow_right_alt,
                              size: 16,
                              color: scheme.outline,
                            ),
                            const SizedBox(width: 2),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 150),
                              child: Text(
                                rule.target,
                                style: mono(
                                  12,
                                  color: scheme.primary,
                                  weight: 600,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                ?trailing,
                Padding(
                  padding: const EdgeInsets.only(right: Insets.sm),
                  child: Icon(
                    Icons.chevron_right,
                    size: 18,
                    color: scheme.outline,
                  ),
                ),
              ],
            ),
            const Hairline(indent: Insets.lg),
          ],
        ),
      ),
    );
  }
}

/// 抓取一个预设规则集的结果。
class _PresetFetch {
  const _PresetFetch(this.preset, {this.body, this.error, this.url, this.text});

  final RulePreset preset;
  final RuleProviderBody? body;

  /// 拉到手的原文。缓存直接写原文：ACL 的 classical 行不能经过 payload 重排。
  final String? text;
  final String? error;

  /// 实际拉到内容的地址（可能是镜像）。写 rule-providers 时用它。
  final String? url;
}

/// 预设面板的返回值：选了哪些规则集、哪些 GEOSITE，代理流量走哪个组。
class _PresetChoice {
  const _PresetChoice(
    this.presets,
    this.geosites,
    this.proxyGroup,
    this.rowGroups,
  );

  final List<RulePreset> presets;
  final List<GeositePick> geosites;

  /// GEOSITE 的目标组（面板里不再让用户选，沿用已有的建议逻辑）。
  final String proxyGroup;

  /// 每个规则集要写进的节点组：空串 = 新建同名组，否则 = 复用的已有组。
  final Map<String, String> rowGroups;

  /// 这个规则集该用哪个组名。
  String groupFor(RulePreset preset) => (rowGroups[preset.id] ?? '').isEmpty
      ? preset.label
      : rowGroups[preset.id]!;
}

/// 「常用规则集」面板：精选（Loyalsoldier + ACL4SSR）与 GEOSITE 服务两组。
class _RulePresetSheet extends StatefulWidget {
  const _RulePresetSheet({required this.proxyGroup, required this.groupNames});

  final String proxyGroup;
  final List<String> groupNames;

  @override
  State<_RulePresetSheet> createState() => _RulePresetSheetState();
}

class _RulePresetSheetState extends State<_RulePresetSheet> {
  late final Set<String> _picked = {
    for (final p in [...kLoyalRulesPresets, ...kAclRulesPresets])
      if (p.enabledByDefault) p.id,
  };
  late final Set<String> _geosites = {
    for (final p in kGeositePicks)
      if (p.enabledByDefault) p.code,
  };
  late final String _proxyGroup = widget.proxyGroup;

  /// 每个规则集要写进的组：没记录 = 新建同名组，有记录 = 复用这个已有组。
  final Map<String, String> _rowGroups = <String, String>{};
  int _tab = 0;

  /// 「缓存于 <时间>」：本地规则集缓存最近一次写入时间。
  String _cacheLabel = '';

  @override
  void initState() {
    super.initState();
    unawaited(_loadCacheLabel());
  }

  Future<void> _loadCacheLabel() async {
    try {
      final cache = await RuleCache.open();
      DateTime? latest;
      for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets]) {
        final at = await cache.fetchedAt(preset.id);
        if (at != null && (latest == null || at.isAfter(latest))) latest = at;
      }
      if (!mounted) return;
      setState(() {
        _cacheLabel = latest == null
            ? '规则集尚未缓存，点「导入」会下载并缓存到本机'
            : '缓存于 ${_formatCacheTime(latest)}（再次导入会刷新）';
      });
    } catch (_) {
      // 缓存时间只是提示，读不到就不显示。
    }
  }

  String _formatCacheTime(DateTime at) {
    final local = at.toLocal();
    String two(int value) => value.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${two(local.hour)}:${two(local.minute)}';
  }

  /// 每个规则集要写进的组：没记录 = 新建同名组，有记录 = 复用这个已有组。
  String _groupFor(RulePreset preset) => _rowGroups[preset.id] ?? '';

  void _setGroup(RulePreset preset, String value) {
    setState(() => _rowGroups[preset.id] = value);
  }

  int get _total => _picked.length + _geosites.length;

  int get _pickedCount => _picked.length;

  int get _presetTotal => kLoyalRulesPresets.length + kAclRulesPresets.length;

  int get _geositeCount => _geosites.length;

  int get _geositeTotal => kGeositePicks.length;

  /// 当前页签全选。
  void _selectAll() {
    setState(() {
      if (_tab == 0) {
        for (final preset in [...kLoyalRulesPresets, ...kAclRulesPresets]) {
          _picked.add(preset.id);
        }
      } else {
        for (final pick in kGeositePicks) {
          _geosites.add(pick.code);
        }
      }
    });
  }

  /// 当前页签清空。
  void _clearAll() {
    setState(() {
      if (_tab == 0) {
        _picked.clear();
      } else {
        _geosites.clear();
      }
    });
  }

  void _toggle(Set<String> target, String key, bool? on) {
    setState(() {
      if (on == true) {
        target.add(key);
      } else {
        target.remove(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('常用规则集'),
      content: SizedBox(
        width: math.min(480, MediaQuery.sizeOf(context).width - 48),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _tabButton(context, 0, '精选', '规则集'),
                  const SizedBox(width: Insets.sm),
                  _tabButton(context, 1, '服务', 'GEOSITE'),
                ],
              ),
              const SizedBox(height: Insets.sm),
              Text(
                _tab == 0
                    ? 'Loyalsoldier 与 ACL4SSR 的规则集，勾选后写成 rule-providers '
                          '并各加一条 RULE-SET（插在 MATCH 之前）。'
                    : '直接用配置里内置的 geosite 数据，离线命中、不额外下载，'
                          '每条写成 GEOSITE（插在 MATCH 之前）。',
                style: theme.textTheme.bodySmall,
              ),
              if (_cacheLabel.isNotEmpty) ...[
                const SizedBox(height: Insets.xs),
                Text(
                  _cacheLabel,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
              const SizedBox(height: Insets.sm),
              Row(
                children: [
                  TextButton(onPressed: _selectAll, child: const Text('全选')),
                  TextButton(onPressed: _clearAll, child: const Text('清空')),
                  const Spacer(),
                  Text(
                    _tab == 0
                        ? '已选 $_pickedCount / $_presetTotal'
                        : '已选 $_geositeCount / $_geositeTotal',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
              if (_tab == 0)
                ..._buildPresets(theme)
              else
                ..._buildGeosites(theme),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _total == 0
              ? null
              : () => Navigator.pop(
                  context,
                  _PresetChoice(
                    [
                      for (final p in [
                        ...kLoyalRulesPresets,
                        ...kAclRulesPresets,
                      ])
                        if (_picked.contains(p.id)) p,
                    ],
                    [
                      for (final p in kGeositePicks)
                        if (_geosites.contains(p.code)) p,
                    ],
                    _proxyGroup,
                    {
                      for (final p in [
                        ...kLoyalRulesPresets,
                        ...kAclRulesPresets,
                      ])
                        if (_picked.contains(p.id)) p.id: _groupFor(p),
                    },
                  ),
                ),
          child: Text(
            '导入 $_total 项（$_pickedCount 规则集 + $_geositeCount GEOSITE）',
          ),
        ),
      ],
    );
  }

  Widget _tabButton(
    BuildContext context,
    int index,
    String label,
    String hint,
  ) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = _tab == index;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => setState(() => _tab = index),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? scheme.primaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(Insets.sm),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: display(
                13,
                weight: 600,
                color: selected ? scheme.onPrimaryContainer : scheme.onSurface,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              hint,
              style: mono(
                10.5,
                color: selected ? scheme.onPrimaryContainer : scheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildPresets(ThemeData theme) {
    final scheme = theme.colorScheme;
    return [
      _sectionTitle(theme, 'Loyalsoldier', '通用、体积小，优先用这批'),
      for (final preset in kLoyalRulesPresets)
        _presetTile(theme, scheme, preset),
      const SizedBox(height: Insets.sm),
      _sectionTitle(theme, 'ACL4SSR', '厂商与流媒体细分，classical 格式'),
      for (final preset in kAclRulesPresets) _presetTile(theme, scheme, preset),
    ];
  }

  Widget _sectionTitle(ThemeData theme, String title, String hint) {
    return Padding(
      padding: const EdgeInsets.only(top: Insets.sm, bottom: 2),
      child: Row(
        children: [
          Text(title, style: display(12, weight: 600)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              hint,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Widget _presetTile(ThemeData theme, ColorScheme scheme, RulePreset preset) {
    final ipBased = preset.behavior == 'ipcidr';
    final group = _groupFor(preset);
    final target = group.isEmpty ? preset.label : group;
    final tile = CheckboxListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      value: _picked.contains(preset.id),
      onChanged: (v) => _toggle(_picked, preset.id, v),
      title: Text(
        '${preset.label}  ·  ${preset.source}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        '${preset.description} → $target'
        '${preset.behavior == 'classical' ? '  ·  classical' : ''}'
        '${ipBased ? '  ·  IP 段' : ''}',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodySmall,
      ),
      secondary: Icon(
        ipBased ? Icons.lan_outlined : Icons.language,
        size: 18,
        color: scheme.primary,
      ),
    );
    final groupPicker = AppDropdown<String>(
      compact: true,
      value: group,
      options: [
        DropdownOption('', '新建同名组'),
        for (final name in widget.groupNames) DropdownOption(name, name),
      ],
      onChanged: (value) => _setGroup(preset, value),
    );

    // 窄屏（手机竖屏）一行放不下勾选框 + 组下拉，中文会被压成逐字竖排；
    // 这种宽度下改成两行：上面整行勾选，下面右对齐放组下拉。
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              tile,
              Align(
                alignment: Alignment.centerRight,
                child: SizedBox(width: 160, child: groupPicker),
              ),
              const SizedBox(height: Insets.xs),
            ],
          );
        }
        return Row(
          children: [
            Expanded(child: tile),
            SizedBox(width: 150, child: groupPicker),
          ],
        );
      },
    );
  }

  List<Widget> _buildGeosites(ThemeData theme) {
    final scheme = theme.colorScheme;
    final groups = <String, List<GeositePick>>{};
    for (final pick in kGeositePicks) {
      groups.putIfAbsent(pick.group, () => []).add(pick);
    }
    return [
      for (final entry in groups.entries) ...[
        _sectionTitle(theme, entry.key, '${entry.value.length} 项'),
        for (final pick in entry.value)
          CheckboxListTile(
            dense: true,
            contentPadding: EdgeInsets.zero,
            value: _geosites.contains(pick.code),
            onChanged: (v) => _toggle(_geosites, pick.code, v),
            title: Text(
              '${pick.label}  ·  ${pick.code}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            subtitle: Text(
              '${pick.description} → ${geositeTargetFor(pick, _proxyGroup)}',
              style: theme.textTheme.bodySmall,
            ),
            secondary: Icon(
              Icons.dns_outlined,
              size: 18,
              color: scheme.primary,
            ),
          ),
      ],
    ];
  }
}
