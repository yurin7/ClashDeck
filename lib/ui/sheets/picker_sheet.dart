import 'package:material_ui/material_ui.dart';

import '../fields.dart';
import '../theme.dart';
import '../widgets.dart';
import '../widgets/selectable_tile.dart';

/// 选择面板的一行。
///
/// 所有「选择」入口（节点 / 规则 / 目标组）都构造 [PickerSheetRow]，
/// 由 [PickerSheetScaffold] 统一渲染，页面不再自己写列表行。
class PickerSheetRow {
  const PickerSheetRow({
    required this.searchText,
    required this.title,
    this.subtitle,
    this.leading,
    this.trailing,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  /// 搜索匹配用的纯文本（面板内部负责过滤）。
  final String searchText;
  final Widget title;
  final Widget? subtitle;
  final Widget? leading;
  final Widget? trailing;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;
}

/// 选择面板的一个分区；顺序由调用方给定（规范：系统策略 → 节点 → 策略组）。
class PickerSheetSection {
  const PickerSheetSection({this.label, required this.rows, this.header});

  final String? label;
  final List<PickerSheetRow> rows;

  /// 分区内可点的自定义头（例如「高级内置（不常用）」折叠头）。
  /// 渲染在 rows 之前，搜索时也保留。
  final Widget? header;
}

/// **唯一**的选择面板骨架：
/// 搜索框 → 全选/反选/清空 + 已选 N → 分区列表（多选高亮行）→ 底部操作栏。
///
/// `NodePickerSheet`、`RulePickerSheet`、`TargetPickerSheet` 都只能基于它，
/// 这些入口共享同一套面板布局与选中态。
class PickerSheetScaffold extends StatefulWidget {
  const PickerSheetScaffold({
    super.key,
    required this.searchHint,
    required this.sections,
    required this.selectedCount,
    required this.onSelectAll,
    required this.onInvert,
    required this.onClear,
    this.footer,
    this.emptyHint = '没有匹配的内容',
    this.toolbar = true,
  });

  final String searchHint;
  final List<PickerSheetSection> sections;
  final int selectedCount;
  final VoidCallback onSelectAll;
  final VoidCallback onInvert;
  final VoidCallback onClear;

  /// 底部操作栏（分隔线 + 左侧辅助 + 右侧取消/确认）。
  final Widget? footer;

  final String emptyHint;

  /// 单选面板可关掉全选/反选/清空那一行。
  final bool toolbar;

  @override
  State<PickerSheetScaffold> createState() => _PickerSheetScaffoldState();
}

class _PickerSheetScaffoldState extends State<PickerSheetScaffold> {
  final TextEditingController _search = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  List<PickerSheetSection> get _visibleSections {
    final keyword = _query.trim().toLowerCase();
    if (keyword.isEmpty) return widget.sections;
    return [
      for (final section in widget.sections)
        PickerSheetSection(
          label: section.label,
          header: section.header,
          rows: [
            for (final row in section.rows)
              if (row.searchText.toLowerCase().contains(keyword)) row,
          ],
        ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final sections = _visibleSections;
    final hasRows = sections.any((section) => section.rows.isNotEmpty);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppTextField(
          controller: _search,
          hint: widget.searchHint,
          prefixIcon: const Icon(Icons.search, size: 18),
          onChanged: (value) => setState(() => _query = value),
        ),
        if (widget.toolbar)
          Padding(
            padding: const EdgeInsets.only(top: Insets.xs),
            child: Row(
              children: [
                TextButton(
                  onPressed: widget.onSelectAll,
                  child: const Text('全选'),
                ),
                TextButton(onPressed: widget.onInvert, child: const Text('反选')),
                TextButton(
                  onPressed: widget.selectedCount == 0 ? null : widget.onClear,
                  child: const Text('清空'),
                ),
                const Spacer(),
                Pill(
                  label: '已选 ${widget.selectedCount}',
                  dense: true,
                  color: Theme.of(context).colorScheme.primary,
                ),
              ],
            ),
          ),
        const SizedBox(height: Insets.xs),
        Flexible(
          child: hasRows
              ? ListView.builder(
                  shrinkWrap: true,
                  itemCount: sections.fold<int>(
                    0,
                    (sum, section) =>
                        sum +
                        section.rows.length +
                        (section.label == null ? 0 : 1) +
                        (section.header == null ? 0 : 1),
                  ),
                  itemBuilder: (context, index) =>
                      _buildItem(context, sections, index),
                )
              : Center(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: Insets.xl),
                    child: Text(widget.emptyHint, style: hintStyle(context)),
                  ),
                ),
        ),
        if (widget.footer != null) ...[
          const SizedBox(height: Insets.sm),
          const Hairline(),
          const SizedBox(height: Insets.sm),
          widget.footer!,
        ],
      ],
    );
  }

  Widget _buildItem(
    BuildContext context,
    List<PickerSheetSection> sections,
    int index,
  ) {
    var cursor = index;
    for (final section in sections) {
      if (section.label != null) {
        if (cursor == 0) {
          return Padding(
            padding: const EdgeInsets.only(top: Insets.xs, bottom: 2),
            child: MicroLabel(section.label!),
          );
        }
        cursor -= 1;
      }
      if (section.header != null) {
        if (cursor == 0) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: section.header,
          );
        }
        cursor -= 1;
      }
      if (cursor < section.rows.length) {
        final row = section.rows[cursor];
        return Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: SelectableTile(
            title: row.title,
            subtitle: row.subtitle,
            leading: row.leading,
            trailing: row.trailing,
            selected: row.selected,
            enabled: row.enabled,
            onTap: row.onTap,
          ),
        );
      }
      cursor -= section.rows.length;
    }
    return const SizedBox.shrink();
  }
}
