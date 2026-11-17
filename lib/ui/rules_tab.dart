import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/edit/geosite_index.dart';
import '../core/edit/import_rules.dart';
import '../core/edit/rule_presets.dart';
import '../core/model/profile.dart';
import '../core/model/rule_types.dart';
import '../core/net/fetch_text.dart';
import '../core/yaml/yaml_doc.dart';
import '../state/editor_state.dart';
import 'import_dialogs.dart';
import 'rule_edit_dialog.dart';
import 'dropdown.dart';
import 'theme.dart';
import 'widgets.dart';

class RulesTab extends StatefulWidget {
  const RulesTab({super.key, required this.state});

  final EditorState state;

  @override
  State<RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends State<RulesTab> {
  EditorState get s => widget.state;

  void _fail() {
    final msg = s.lastError;
    if (msg == null) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _editRule({RuleEntry? initial, int? index}) async {
    final profile = s.profile;
    final targets = <String>{
      ...profile.allTargets,
      if (initial != null) initial.target,
    }.toList();

    final result = await showDialog<Object>(
      context: context,
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
      if (!s.deleteRule(index!)) _fail();
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
    // 新规则插到兜底规则（MATCH/FINAL）之前——追加到最后会让 MATCH 后面还有
    // 规则，内核根本不读，校验器也会报「MATCH 必须最后一条」。
    final terminalAt = s.profile.rules.indexWhere((r) => r.isTerminal);
    final ok = index == null
        ? s.addRule(rule, at: terminalAt < 0 ? null : terminalAt)
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
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(e.message)));
      return;
    }
    if (outcome.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(
          SnackBar(
            content: Text(
              outcome.warnings.isEmpty
                  ? '没有可导入的规则'
                  : '没有可导入的规则：${outcome.warnings.first}',
            ),
          ),
        );
      return;
    }
    if (!s.apply((_) => outcome.doc)) {
      _fail();
      return;
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('已导入：${outcome.summary}')));
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
    final choice = await showDialog<_PresetChoice>(
      context: context,
      builder: (_) => _RulePresetSheet(
        proxyGroup: suggestProxyGroup(groupNames),
        groupNames: groupNames,
      ),
    );
    if (choice == null) return;
    if (choice.presets.isEmpty && choice.geosites.isEmpty) return;

    var doc = s.doc;
    final applied = <String>[];
    final failed = <String>[];
    var updated = 0;

    if (choice.presets.isNotEmpty) {
      final fetched = await _withBusy(
        '正在拉取 ${choice.presets.length} 个规则集…',
        () => Future.wait(choice.presets.map(_fetchPreset)),
      );
      for (final item in fetched) {
        final body = item.body;
        if (body == null) {
          failed.add('${item.preset.id}（${item.error ?? '解析失败'}）');
          continue;
        }
        try {
          final outcome = importRuleProvider(
            doc,
            body: body,
            name: item.preset.id,
            target: presetTargetFor(item.preset, choice.proxyGroup),
            url: item.preset.url,
          );
          doc = outcome.doc;
          applied.add(item.preset.id);
          updated += outcome.providersUpdated.length;
        } on ConfigEditException catch (e) {
          failed.add('${item.preset.id}（${e.message}）');
        }
      }
    }

    var geoAdded = 0;
    if (choice.geosites.isNotEmpty) {
      // 一次最多 50 条，免得一口气把规则列表撑得太长。
      final lines = [
        for (final pick in choice.geosites.take(50))
          'GEOSITE,${pick.code},${geositeTargetFor(pick, choice.proxyGroup)}',
      ];
      try {
        final outcome = insertRuleLines(doc, lines);
        doc = outcome.doc;
        geoAdded = outcome.rulesAdded;
        failed.addAll(outcome.warnings);
      } on ConfigEditException catch (e) {
        failed.add('GEOSITE（${e.message}）');
      }
    }

    if (applied.isEmpty && geoAdded == 0) {
      _toast('一个都没导入成功：${failed.isEmpty ? '未知原因' : failed.first}');
      return;
    }
    if (!s.apply((_) => doc)) {
      _fail();
      return;
    }
    final parts = <String>[
      if (applied.isNotEmpty) '${applied.length} 组规则集',
      if (geoAdded > 0) 'GEOSITE $geoAdded 条',
      if (updated > 0) '更新 $updated 个同名规则集',
    ];
    _toast(
      failed.isEmpty
          ? '已导入 ${parts.join(' + ')}'
          : '已导入 ${parts.join(' + ')}，${failed.length} 项失败：${failed.first}',
    );
  }

  Future<_PresetFetch> _fetchPreset(RulePreset preset) async {
    try {
      final text = await fetchText(preset.url);
      final parsed = parseRuleProviderBody(text, url: preset.url);
      if (parsed == null) {
        return _PresetFetch(preset, error: '没识别出规则集内容');
      }
      return _PresetFetch(preset, body: parsed);
    } on ConfigEditException catch (e) {
      return _PresetFetch(preset, error: e.message);
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  /// 跑一个异步任务，期间盖一层「正在…」的对话框。
  Future<T> _withBusy<T>(String message, Future<T> Function() task) async {
    final navigator = Navigator.of(context, rootNavigator: true);
    var closed = false;
    unawaited(
      showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          content: Row(
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
              : ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    Insets.xs,
                    Insets.lg,
                    Insets.md,
                  ),
                  itemCount: rules.length,
                  buildDefaultDragHandles: false,
                  // onReorderItem 已经把"移除后下标"算好，不必再 -1。
                  onReorderItem: (oldIndex, newIndex) {
                    if (oldIndex == newIndex) return;
                    if (!s.moveRule(oldIndex, newIndex)) _fail();
                  },
                  itemBuilder: (context, i) {
                    final rule = rules[i];
                    return Padding(
                      key: ValueKey('rule-${rule.index}'),
                      padding: const EdgeInsets.only(bottom: Insets.sm),
                      child: _RuleRow(
                        rule: rule,

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
                        onTap: () =>
                            _editRule(initial: rule, index: rule.index),
                      ),
                    );
                  },
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
  });

  final RuleEntry rule;

  final Widget dragHandle;
  final VoidCallback onTap;

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
  const _PresetFetch(this.preset, {this.body, this.error});

  final RulePreset preset;
  final RuleProviderBody? body;
  final String? error;
}

/// 预设面板的返回值：选了哪些规则集、哪些 GEOSITE，代理流量走哪个组。
class _PresetChoice {
  const _PresetChoice(this.presets, this.geosites, this.proxyGroup);

  final List<RulePreset> presets;
  final List<GeositePick> geosites;
  final String proxyGroup;
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
  late String _proxyGroup = widget.proxyGroup;
  int _tab = 0;

  int get _total => _picked.length + _geosites.length;

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
        width: 480,
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
              const SizedBox(height: Insets.sm),
              AppDropdown<String>(
                label: '代理流量走哪个组',
                expand: true,
                value: _proxyGroup,
                options: [
                  for (final name in widget.groupNames)
                    DropdownOption(name, name),
                ],
                onChanged: (v) => setState(() => _proxyGroup = v),
              ),
              const SizedBox(height: Insets.sm),
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
                  ),
                ),
          child: Text('导入 $_total 项'),
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
    return CheckboxListTile(
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
        '${preset.description} → ${presetTargetFor(preset, _proxyGroup)}'
        '${preset.behavior == 'classical' ? '  ·  classical' : ''}'
        '${ipBased ? '  ·  IP 段' : ''}',
        style: theme.textTheme.bodySmall,
      ),
      secondary: Icon(
        ipBased ? Icons.lan_outlined : Icons.language,
        size: 18,
        color: scheme.primary,
      ),
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
