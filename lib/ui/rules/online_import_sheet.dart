import 'package:material_ui/material_ui.dart';

import '../../core/edit/rule_presets.dart';
import '../theme.dart';
import '../widgets.dart';
import '../fields.dart';
import 'import_sheet_style.dart';

/// 在线面板的返回值：要么勾选了一组预置规则集，要么填了一个自定义地址。
sealed class OnlineImportRequest {
  const OnlineImportRequest();
}

class OnlinePresetRequest extends OnlineImportRequest {
  const OnlinePresetRequest(this.presets);

  final List<RulePreset> presets;
}

class OnlineCustomUrlRequest extends OnlineImportRequest {
  const OnlineCustomUrlRequest(this.url);

  final String url;
}

/// 底部滑入的在线规则集面板。
///
/// 这里只负责「挑什么」，不碰配置：勾选结果、自定义地址都通过
/// [OnlineImportRequest] 交回规则页，由 core 里的 `online_import.dart`
/// 算出预览再落地，目标组一律 DEFAULT。
Future<OnlineImportRequest?> showOnlineImportSheet(BuildContext context) {
  return showGeneralDialog<OnlineImportRequest>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => const _OnlineImportSheet(),
    transitionBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.12),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class _OnlineImportSheet extends StatefulWidget {
  const _OnlineImportSheet();

  @override
  State<_OnlineImportSheet> createState() => _OnlineImportSheetState();
}

class _OnlineImportSheetState extends State<_OnlineImportSheet> {
  static final RegExp _urlPattern = RegExp(r'^https?://\S+$');

  final Set<String> _picked = <String>{};
  final Set<String> _collapsed = <String>{};
  final TextEditingController _urlCtrl = TextEditingController(
    text: 'https://',
  );
  String? _urlError;

  static const List<({String title, String hint, List<RulePreset> presets})>
  _groups = [
    (
      title: 'Loyalsoldier',
      hint: '按大分类拆分，域名 / IP 都有',
      presets: kLoyalRulesPresets,
    ),
    (title: 'ACL4SSR', hint: '按服务拆分，适合逐个点名', presets: kAclRulesPresets),
  ];

  @override
  void dispose() {
    disposeAfterDialog(_urlCtrl);
    super.dispose();
  }

  List<RulePreset> get _all => [for (final group in _groups) ...group.presets];

  void _togglePreset(RulePreset preset, bool? value) {
    setState(() {
      if (value == true) {
        _picked.add(preset.id);
      } else {
        _picked.remove(preset.id);
      }
    });
  }

  void _setGroup(List<RulePreset> presets, {required bool selected}) {
    setState(() {
      for (final preset in presets) {
        if (selected) {
          _picked.add(preset.id);
        } else {
          _picked.remove(preset.id);
        }
      }
    });
  }

  void _submitPresets() {
    final chosen = [
      for (final preset in _all)
        if (_picked.contains(preset.id)) preset,
    ];
    if (chosen.isEmpty) return;
    Navigator.of(context).pop(OnlinePresetRequest(chosen));
  }

  void _submitUrl() {
    final url = _urlCtrl.text.trim();
    if (!_urlPattern.hasMatch(url)) {
      setState(() => _urlError = '地址要以 http:// 或 https:// 开头，且不含空格');
      return;
    }
    Navigator.of(context).pop(OnlineCustomUrlRequest(url));
  }

  String _hint(RulePreset preset) {
    if (preset.description.isNotEmpty) return preset.description;
    return switch (preset.behavior) {
      'domain' => '域名规则集',
      'ipcidr' => 'IP 段规则集',
      _ => '经典规则集',
    };
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: const EdgeInsets.only(
          left: Insets.sm,
          right: Insets.sm,
          bottom: Insets.sm,
        ),
        child: Material(
          color: scheme.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(Insets.xl),
          clipBehavior: Clip.antiAlias,
          child: SizedBox(
            height: importSheetMaxHeight(context),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.only(top: Insets.sm),
                  child: Center(
                    child: Container(
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                        color: scheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.xl,
                    Insets.md,
                    Insets.lg,
                    Insets.xs,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('在线规则集', style: display(17, weight: 700)),
                            const SizedBox(height: 2),
                            Text(
                              '按整包匹配 · 目标统一写入 DEFAULT',
                              style: hintStyle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      importSheetAction(
                        label: '全部',
                        onPressed: () => _setGroup(_all, selected: true),
                      ),
                      importSheetAction(
                        label: '清空全部',
                        onPressed: _picked.isEmpty
                            ? null
                            : () => _setGroup(_all, selected: false),
                      ),
                    ],
                  ),
                ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      Insets.lg,
                      0,
                      Insets.lg,
                      Insets.md,
                    ),
                    children: [
                      for (final group in _groups) _buildGroup(context, group),
                      _buildCustomUrl(context, scheme),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    0,
                    Insets.lg,
                    Insets.md,
                  ),
                  child: SizedBox(
                    width: double.infinity,
                    child: FilledButton(
                      onPressed: _picked.isEmpty ? null : _submitPresets,
                      child: Text('导入 ${_picked.length} 个'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildGroup(
    BuildContext context,
    ({String title, String hint, List<RulePreset> presets}) group,
  ) {
    final scheme = Theme.of(context).colorScheme;
    final open = !_collapsed.contains(group.title);
    final pickedCount = group.presets
        .where((preset) => _picked.contains(preset.id))
        .length;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: importSheetCard(
        context,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => setState(() {
                      if (open) {
                        _collapsed.add(group.title);
                      } else {
                        _collapsed.remove(group.title);
                      }
                    }),
                    borderRadius: BorderRadius.circular(Radiuses.md),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(
                        Insets.md,
                        Insets.sm,
                        Insets.sm,
                        Insets.sm,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            open ? Icons.expand_more : Icons.chevron_right,
                            size: 18,
                            color: scheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: Insets.xs),
                          Text(group.title, style: display(13.5, weight: 700)),
                          const SizedBox(width: Insets.sm),
                          Expanded(
                            child: Text(
                              pickedCount == 0
                                  ? group.hint
                                  : '已选 $pickedCount / ${group.presets.length}',
                              style: hintStyle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
                  ),
                  onPressed: () => _setGroup(group.presets, selected: true),
                  child: const Text('全选'),
                ),
                TextButton(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
                  ),
                  onPressed: pickedCount == 0
                      ? null
                      : () => _setGroup(group.presets, selected: false),
                  child: const Text('清空'),
                ),
                const SizedBox(width: Insets.xs),
              ],
            ),
            if (open)
              for (final preset in group.presets)
                CheckboxListTile(
                  value: _picked.contains(preset.id),
                  onChanged: (value) => _togglePreset(preset, value),
                  dense: true,
                  controlAffinity: ListTileControlAffinity.leading,
                  contentPadding: const EdgeInsets.only(
                    left: Insets.sm,
                    right: Insets.md,
                  ),
                  visualDensity: VisualDensity.compact,
                  title: Text(
                    preset.label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    _hint(preset),
                    style: hintStyle(context)?.copyWith(fontSize: 11),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
          ],
        ),
      ),
    );
  }

  Widget _buildCustomUrl(BuildContext context, ColorScheme scheme) {
    return importSheetCard(
      context,
      child: Padding(
        padding: const EdgeInsets.all(Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.link, size: 16, color: scheme.onSurfaceVariant),
                const SizedBox(width: Insets.xs),
                Text('自定义地址', style: display(13.5, weight: 700)),
              ],
            ),
            const SizedBox(height: 2),
            Text(
              '任意 http/https 规则集地址，目标同样是 DEFAULT',
              style: hintStyle(context),
            ),
            const SizedBox(height: Insets.sm),
            AppTextField(
              controller: _urlCtrl,
              keyboardType: TextInputType.url,
              hint: 'https://example.com/rules.txt',
              error: _urlError,
              onChanged: (_) {
                if (_urlError != null) setState(() => _urlError = null);
              },
            ),
            const SizedBox(height: Insets.sm),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _submitUrl,
                icon: const Icon(Icons.download_outlined, size: 18),
                label: const Text('导入这个地址'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
