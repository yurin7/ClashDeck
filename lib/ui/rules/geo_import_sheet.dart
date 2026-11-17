import 'package:material_ui/material_ui.dart';

import '../../core/edit/geosite_index.dart';
import '../../core/edit/import_plan.dart';
import '../../core/edit/rule_presets.dart';
import '../theme.dart';
import '../widgets.dart';

/// 一个可勾选的 GEO 词库。
class _GeoItem {
  const _GeoItem({
    required this.code,
    required this.label,
    required this.group,
  });

  final String code;
  final String label;
  final String group;
}

/// 底部滑入的 GEO 词库面板，返回选中的 code 列表。
///
/// 预置列表来自 [kGeositePicks]（有中文名、有分类），再补上
/// [kGeositeLabels] 里没进精选的词库；配置里已有的 code 显示「已添加」
/// 且不可再选，避免重复写 `GEOSITE` 行。
Future<List<String>?> showGeoImportSheet(
  BuildContext context, {
  Set<String> existingCodes = const {},
}) {
  return showGeneralDialog<List<String>>(
    context: context,
    barrierDismissible: true,
    barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    barrierColor: Colors.black54,
    transitionDuration: const Duration(milliseconds: 240),
    pageBuilder: (_, _, _) => _GeoImportSheet(existingCodes: existingCodes),
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

class _GeoImportSheet extends StatefulWidget {
  const _GeoImportSheet({required this.existingCodes});

  final Set<String> existingCodes;

  @override
  State<_GeoImportSheet> createState() => _GeoImportSheetState();
}

class _GeoImportSheetState extends State<_GeoImportSheet> {
  final List<String> _picked = <String>[];
  final TextEditingController _searchCtrl = TextEditingController();
  late final List<_GeoItem> _items;
  late final List<String> _groups;
  late final Set<String> _existing;
  late String _group;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _existing = {for (final code in widget.existingCodes) code.toLowerCase()};
    _items = _buildItems();
    _groups = <String>{for (final item in _items) item.group}.toList();
    _group = _groups.isEmpty ? '' : _groups.first;
  }

  @override
  void dispose() {
    disposeAfterDialog(_searchCtrl);
    super.dispose();
  }

  static List<_GeoItem> _buildItems() {
    final items = <_GeoItem>[];
    final seen = <String>{};
    for (final pick in kGeositePicks) {
      if (!seen.add(pick.code)) continue;
      items.add(
        _GeoItem(code: pick.code, label: pick.label, group: pick.group),
      );
    }
    for (final entry in kGeositeLabels.entries) {
      if (!seen.add(entry.key)) continue;
      items.add(_GeoItem(code: entry.key, label: entry.value, group: '其他'));
    }
    return items;
  }

  String get _searching => _query.trim().toLowerCase();

  bool get _hasFreeInput =>
      _searching.isNotEmpty &&
      isValidGeositeCode(_searching) &&
      !_existing.contains(_searching) &&
      !_items.any((item) => item.code == _searching);

  List<_GeoItem> get _visible {
    if (_searching.isNotEmpty) {
      return [
        for (final item in _items)
          if (item.code.contains(_searching) ||
              item.label.toLowerCase().contains(_searching))
            item,
      ];
    }
    return [
      for (final item in _items)
        if (item.group == _group) item,
    ];
  }

  void _toggle(String code, bool? value) {
    setState(() {
      if (value == true) {
        if (!_picked.contains(code)) _picked.add(code);
      } else {
        _picked.remove(code);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.82;
    final visible = _visible;
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
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
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
                    Insets.xl,
                    Insets.xs,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('GEO 数据', style: display(17, weight: 700)),
                      const SizedBox(height: 2),
                      Text(
                        'GEOSITE 离线命中；目标统一写入 DEFAULT 组',
                        style: hintStyle(context),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    0,
                    Insets.lg,
                    Insets.xs,
                  ),
                  child: TextField(
                    controller: _searchCtrl,
                    autocorrect: false,
                    style: mono(12.5),
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search, size: 18),
                      hintText: '搜索代码或中文名',
                    ),
                    onChanged: (value) => setState(() => _query = value),
                  ),
                ),
                if (_searching.isEmpty)
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(
                        horizontal: Insets.lg,
                      ),
                      children: [
                        for (final group in _groups)
                          Padding(
                            padding: const EdgeInsets.only(right: Insets.xs),
                            child: ChoiceChip(
                              label: Text(
                                group,
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: group == _group,
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => setState(() => _group = group),
                            ),
                          ),
                      ],
                    ),
                  ),
                Flexible(
                  child: ListView(
                    shrinkWrap: true,
                    padding: const EdgeInsets.fromLTRB(
                      Insets.sm,
                      Insets.xs,
                      Insets.sm,
                      Insets.sm,
                    ),
                    children: [
                      if (_hasFreeInput) _buildFreeInput(context, _searching),
                      for (final item in visible) _buildRow(context, item),
                      if (visible.isEmpty && !_hasFreeInput)
                        Padding(
                          padding: const EdgeInsets.all(Insets.lg),
                          child: Text(
                            _searching.isEmpty
                                ? '这个分类暂时没有词库'
                                : '没有匹配的词库；输入纯小写代码可以直接用',
                            style: hintStyle(context),
                          ),
                        ),
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
                      onPressed: _picked.isEmpty
                          ? null
                          : () => Navigator.of(context).pop([..._picked]),
                      child: Text('添加 ${_picked.length} 条'),
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

  Widget _buildFreeInput(BuildContext context, String code) {
    final scheme = Theme.of(context).colorScheme;
    return CheckboxListTile(
      value: _picked.contains(code),
      onChanged: (value) => _toggle(code, value),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.only(left: Insets.sm, right: Insets.sm),
      visualDensity: VisualDensity.compact,
      title: Text(
        '＋ 直接使用 $code',
        style: mono(12.5, color: scheme.secondary, weight: 600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text('不在预置列表里，内核认识就能用', style: hintStyle(context)),
    );
  }

  Widget _buildRow(BuildContext context, _GeoItem item) {
    final already = _existing.contains(item.code);
    return CheckboxListTile(
      value: already || _picked.contains(item.code),
      onChanged: already ? null : (value) => _toggle(item.code, value),
      dense: true,
      controlAffinity: ListTileControlAffinity.leading,
      contentPadding: const EdgeInsets.only(left: Insets.sm, right: Insets.sm),
      visualDensity: VisualDensity.compact,
      title: Text(
        item.code,
        style: mono(12.5, weight: already ? 400 : 600),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Text(
        item.label,
        style: hintStyle(context)?.copyWith(fontSize: 11),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      secondary: already
          ? Pill(
              label: '已添加',
              dense: true,
              color: Theme.of(context).colorScheme.outline,
            )
          : null,
    );
  }
}
