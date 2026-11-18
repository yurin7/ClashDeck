import 'package:material_ui/material_ui.dart';

import '../../core/edit/geosite_index.dart';
import '../../core/edit/import_plan.dart';
import '../../core/edit/rule_presets.dart';
import '../theme.dart';
import '../widgets.dart';
import 'import_sheet_style.dart';

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
///
/// 分类用 PageView 承载：点 chip 切页、左右滑列表也能切页，内容区高度
/// 固定，切分类不会让面板忽高忽低。
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
  final PageController _pageController = PageController();
  final Map<int, GlobalKey> _chipKeys = <int, GlobalKey>{};
  late final List<_GeoItem> _items;
  late final List<String> _groups;
  late final Map<String, List<_GeoItem>> _byGroup;
  late final Set<String> _existing;
  int _index = 0;
  String _query = '';

  @override
  void initState() {
    super.initState();
    _existing = {for (final code in widget.existingCodes) code.toLowerCase()};
    _items = _buildItems();
    _byGroup = <String, List<_GeoItem>>{};
    for (final item in _items) {
      (_byGroup[item.group] ??= <_GeoItem>[]).add(item);
    }
    _groups = _byGroup.keys.toList();
  }

  @override
  void dispose() {
    _pageController.dispose();
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

  List<_GeoItem> get _searchMatches {
    if (_searching.isEmpty) return const <_GeoItem>[];
    return [
      for (final item in _items)
        if (item.code.contains(_searching) ||
            item.label.toLowerCase().contains(_searching))
          item,
    ];
  }

  List<_GeoItem> _itemsOf(int index) => index >= 0 && index < _groups.length
      ? _byGroup[_groups[index]]!
      : const [];

  void _toggle(String code, bool? value) {
    setState(() {
      if (value == true) {
        if (!_picked.contains(code)) _picked.add(code);
      } else {
        _picked.remove(code);
      }
    });
  }

  /// 勾选 / 取消一整批词库（跳过已在配置里的）。
  void _setAll(Iterable<_GeoItem> items, {required bool selected}) {
    setState(() {
      for (final item in items) {
        if (_existing.contains(item.code)) continue;
        if (selected) {
          if (!_picked.contains(item.code)) _picked.add(item.code);
        } else {
          _picked.remove(item.code);
        }
      }
    });
  }

  void _goToCategory(int index) {
    if (index < 0 || index >= _groups.length) return;
    setState(() => _index = index);
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        index,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    }
    _centerChip(index);
  }

  /// 只把「当前这个 chip」滚到中间，避免整条 chip 条抖动。
  void _centerChip(int index) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _chipKeys[index]?.currentContext;
      if (ctx == null) return;
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final current = _itemsOf(_index);
    final selectedHere = current
        .where((item) => _picked.contains(item.code))
        .length;
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
            key: const ValueKey('geo-import-sheet'),
            height: importSheetMaxHeight(context),
            child: Column(
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
                            Text('GEO 数据', style: display(17, weight: 700)),
                            const SizedBox(height: 2),
                            Text(
                              'GEOSITE 离线命中 · 目标统一写入 DEFAULT',
                              style: hintStyle(context),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      importSheetAction(
                        label: '全部',
                        onPressed: () => _setAll(_items, selected: true),
                      ),
                      importSheetAction(
                        label: '清空全部',
                        onPressed: _picked.isEmpty
                            ? null
                            : () => _setAll(_items, selected: false),
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
                        for (var i = 0; i < _groups.length; i++)
                          Padding(
                            padding: const EdgeInsets.only(right: Insets.xs),
                            child: ChoiceChip(
                              key: _chipKeys.putIfAbsent(i, GlobalKey.new),
                              label: Text(
                                _groups[i],
                                style: const TextStyle(fontSize: 12),
                              ),
                              selected: i == _index,
                              showCheckmark: false,
                              visualDensity: VisualDensity.compact,
                              onSelected: (_) => _goToCategory(i),
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.lg,
                      Insets.xs,
                      Insets.lg,
                      0,
                    ),
                    child: importSheetCard(
                      context,
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(
                              Insets.sm,
                              0,
                              Insets.sm,
                              0,
                            ),
                            child: Row(
                              children: [
                                importSheetAction(
                                  label: '全选',
                                  onPressed: current.isEmpty
                                      ? null
                                      : () => _setAll(current, selected: true),
                                ),
                                Text(
                                  '已选 $selectedHere',
                                  style: hintStyle(context)
                                      ?.copyWith(fontSize: 11),
                                ),
                                const Spacer(),
                                importSheetAction(
                                  label: '清空',
                                  onPressed: selectedHere == 0
                                      ? null
                                      : () => _setAll(current, selected: false),
                                ),
                              ],
                            ),
                          ),
                          Expanded(child: _buildContent(context)),
                        ],
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Insets.lg,
                    Insets.md,
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

  Widget _buildContent(BuildContext context) {
    if (_searching.isNotEmpty) return _buildSearchResults(context);
    if (_groups.isEmpty) {
      return Center(child: Text('这个分类暂时没有词库', style: hintStyle(context)));
    }
    return PageView.builder(
      controller: _pageController,
      itemCount: _groups.length,
      onPageChanged: (index) {
        setState(() => _index = index);
        _centerChip(index);
      },
      itemBuilder: (context, index) => _GeoPage(
        key: PageStorageKey<String>(_groups[index]),
        items: _itemsOf(index),
        existing: _existing,
        picked: _picked,
        onToggle: _toggle,
        emptyText: '该分类暂无数据',
      ),
    );
  }

  Widget _buildSearchResults(BuildContext context) {
    final matches = _searchMatches;
    return ListView(
      padding: const EdgeInsets.fromLTRB(Insets.xs, 0, Insets.xs, Insets.sm),
      children: [
        if (_hasFreeInput) _buildFreeInput(context, _searching),
        for (final item in matches)
          _GeoRow(
            item: item,
            existing: _existing,
            picked: _picked,
            onToggle: _toggle,
          ),
        if (matches.isEmpty && !_hasFreeInput)
          Padding(
            padding: const EdgeInsets.all(Insets.lg),
            child: Text('没有匹配的词库；输入纯小写代码可以直接用', style: hintStyle(context)),
          ),
      ],
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
}

/// 一个分类页：自己保持滚动位置（切分类回来还在原处）。
class _GeoPage extends StatefulWidget {
  const _GeoPage({
    super.key,
    required this.items,
    required this.existing,
    required this.picked,
    required this.onToggle,
    required this.emptyText,
  });

  final List<_GeoItem> items;
  final Set<String> existing;
  final List<String> picked;
  final void Function(String code, bool? value) onToggle;
  final String emptyText;

  @override
  State<_GeoPage> createState() => _GeoPageState();
}

class _GeoPageState extends State<_GeoPage> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    if (widget.items.isEmpty) {
      return Center(child: Text(widget.emptyText, style: hintStyle(context)));
    }
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(Insets.xs, 0, Insets.xs, Insets.sm),
      itemCount: widget.items.length,
      itemBuilder: (context, index) => _GeoRow(
        item: widget.items[index],
        existing: widget.existing,
        picked: widget.picked,
        onToggle: widget.onToggle,
      ),
    );
  }
}

/// 一行可勾选的词库。
class _GeoRow extends StatelessWidget {
  const _GeoRow({
    required this.item,
    required this.existing,
    required this.picked,
    required this.onToggle,
  });

  final _GeoItem item;
  final Set<String> existing;
  final List<String> picked;
  final void Function(String code, bool? value) onToggle;

  @override
  Widget build(BuildContext context) {
    final already = existing.contains(item.code);
    return CheckboxListTile(
      value: already || picked.contains(item.code),
      onChanged: already ? null : (value) => onToggle(item.code, value),
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
