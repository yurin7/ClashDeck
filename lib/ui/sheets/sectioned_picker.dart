import 'package:material_ui/material_ui.dart';

import '../widgets/select_sheet.dart';
import 'picker_sheet.dart';

/// 单选选择面板的一项：value 是被选中的值，chip 是整行的展示胶囊。
class SectionedPickerItem<T> {
  const SectionedPickerItem({
    required this.value,
    required this.chip,
    this.searchText = '',
    this.subtitle,
    this.selected = false,
    this.enabled = true,
  });

  final T value;
  final Widget chip;
  final String searchText;
  final Widget? subtitle;
  final bool selected;
  final bool enabled;
}

/// 单选选择面板的一个分区：label 是分区标题，header 是标题下、行以上的自定义头。
///
/// [collapsible] 为 true 时，分区渲染成一个折叠头（默认收起），收起文案是
/// `<collapsedLabel>（N）`，展开文案是 [expandedLabel]。例如目标面板的
/// 「高级内置（不常用）」。
class SectionedPickerSection<T> {
  const SectionedPickerSection({
    this.label,
    this.header,
    required this.items,
    this.collapsible = false,
    this.collapsedLabel = '更多选项',
    this.expandedLabel = '收起',
  });

  final String? label;
  final Widget? header;
  final List<SectionedPickerItem<T>> items;
  final bool collapsible;
  final String collapsedLabel;
  final String expandedLabel;
}

/// 通用单选面板：复用 [PickerSheetScaffold]，所有「选一个」入口都应走这里。
///
/// 分区顺序由调用方给定；[SectionedPickerSection.collapsible] 的分区默认收起。
Future<T?> showSectionedPicker<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<SectionedPickerSection<T>> sections,
  String searchHint = '搜索',
  String emptyHint = '没有匹配的内容',
}) {
  return showSelectSheet<T>(
    context,
    title: title,
    subtitle: subtitle,
    body: (_) => _SectionedPickerBody<T>(
      sections: sections,
      searchHint: searchHint,
      emptyHint: emptyHint,
    ),
  );
}

class _SectionedPickerBody<T> extends StatefulWidget {
  const _SectionedPickerBody({
    required this.sections,
    required this.searchHint,
    required this.emptyHint,
  });

  final List<SectionedPickerSection<T>> sections;
  final String searchHint;
  final String emptyHint;

  @override
  State<_SectionedPickerBody<T>> createState() =>
      _SectionedPickerBodyState<T>();
}

class _SectionedPickerBodyState<T> extends State<_SectionedPickerBody<T>> {
  final Set<int> _expanded = <int>{};

  @override
  Widget build(BuildContext context) {
    return PickerSheetScaffold(
      searchHint: widget.searchHint,
      emptyHint: widget.emptyHint,
      toolbar: false,
      sections: [
        for (var index = 0; index < widget.sections.length; index++)
          _buildSection(context, index, widget.sections[index]),
      ],
      selectedCount: 0,
      onSelectAll: () {},
      onInvert: () {},
      onClear: () {},
    );
  }

  PickerSheetSection _buildSection(
    BuildContext context,
    int index,
    SectionedPickerSection<T> section,
  ) {
    final collapsed = section.collapsible && !_expanded.contains(index);
    return PickerSheetSection(
      label: collapsed ? null : section.label,
      header: section.collapsible
          ? Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: () => setState(() {
                  if (!_expanded.remove(index)) _expanded.add(index);
                }),
                icon: Icon(
                  collapsed ? Icons.expand_more : Icons.expand_less,
                  size: 18,
                ),
                label: Text(
                  collapsed
                      ? '${section.collapsedLabel}（${section.items.length}）'
                      : section.expandedLabel,
                ),
              ),
            )
          : section.header,
      rows: [
        if (!collapsed)
          for (final item in section.items)
            PickerSheetRow(
              searchText: item.searchText.isEmpty
                  ? '${item.value}'
                  : item.searchText,
              title: item.chip,
              subtitle: item.subtitle,
              selected: item.selected,
              enabled: item.enabled,
              onTap: () => Navigator.of(context).pop(item.value),
            ),
      ],
    );
  }
}
