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

/// 单选选择面板的一个分区：label 是分区标题，header 是标题下、行以上的自定义头
/// （例如「高级内置（不常用）」折叠头），items 是可选行。
class SectionedPickerSection<T> {
  const SectionedPickerSection({this.label, this.header, required this.items});

  final String? label;
  final Widget? header;
  final List<SectionedPickerItem<T>> items;
}

/// 通用单选面板：复用 [PickerSheetScaffold]，所有「选一个」入口都应走这里。
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
    body: (_) => PickerSheetScaffold(
      searchHint: searchHint,
      emptyHint: emptyHint,
      toolbar: false,
      sections: [
        for (final section in sections)
          PickerSheetSection(
            label: section.label,
            header: section.header,
            rows: [
              for (final item in section.items)
                PickerSheetRow(
                  searchText: item.searchText,
                  title: item.chip,
                  subtitle: item.subtitle,
                  selected: item.selected,
                  enabled: item.enabled,
                  onTap: () => Navigator.of(context).pop(item.value),
                ),
            ],
          ),
      ],
      selectedCount: 0,
      onSelectAll: () {},
      onInvert: () {},
      onClear: () {},
    ),
  );
}
