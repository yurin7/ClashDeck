import 'package:material_ui/material_ui.dart';

import '../../core/edit/rule_targets.dart';
import '../../core/model/profile.dart';
import '../chips.dart';
import '../fields.dart';
import '../sheets/sectioned_picker.dart';
import '../theme.dart';
import 'app_ink.dart';

/// 所有「目标组」输入的唯一组件：点开 = 选择面板（分类 + 胶囊 + 高亮行）。
///
/// 不再用 `AppDropdown` 选目标；编辑规则、导入规则、改挂规则等入口都走这里，
/// 这样以后只改一处，所有入口一起变。见 docs/DESIGN_SYSTEM.md 第 7.B 节。
class TargetSelectorField extends StatelessWidget {
  const TargetSelectorField({
    super.key,
    required this.value,
    required this.options,
    this.otherOptions = const <String>[],
    this.label = '目标（策略 / 组）',
    this.emptyLabel,
    this.enabled = true,
    this.onChanged,
  });

  final String value;

  /// 主列表：自定义组 / DEFAULT / 自动选择 / 系统策略等。
  final List<String> options;

  /// 高级内置（REJECT-DROP / PASS / COMPATIBLE / GLOBAL），默认收起。
  final List<String> otherOptions;

  final String label;

  /// 空值时的展示文案（例如导入规则里的「（默认）用规则集名称」）。
  final String? emptyLabel;

  final bool enabled;
  final ValueChanged<String>? onChanged;

  Future<void> _open(BuildContext context) async {
    final picked = await showTargetPickerSheet(
      context,
      title: label,
      options: options,
      otherOptions: otherOptions,
      current: value,
      emptyLabel: emptyLabel,
    );
    if (picked != null) onChanged?.call(picked);
  }

  @override
  Widget build(BuildContext context) {
    final showEmpty = value.isEmpty && emptyLabel != null;
    return AppInkWell(
      borderRadius: BorderRadius.circular(Radiuses.md),
      onTap: enabled && onChanged != null ? () => _open(context) : null,
      child: InputDecorator(
        decoration: fieldDecoration(label: label, enabled: enabled),
        child: Align(
          alignment: Alignment.centerLeft,
          child: showEmpty
              ? Text(emptyLabel!, style: hintStyle(context))
              : NameChip(name: value),
        ),
      ),
    );
  }
}

/// 打开「选目标」面板，返回值：null = 取消，'' = 选了空选项，其它 = 选中的名字。
///
/// 全局出口、组内节点、规则改挂这些入口都复用它，保证和「编辑规则」里
/// 选目标是同一套面板（分类 + 胶囊 + 高亮行 + 搜索）。
Future<String?> showTargetPickerSheet(
  BuildContext context, {
  required String title,
  String? subtitle,
  required List<String> options,
  List<String> otherOptions = const <String>[],
  String current = '',
  String? emptyLabel,
  Map<String, String?> subtitles = const <String, String?>{},
}) {
  final advanced = otherOptions;
  final primary = [
    for (final name in options)
      if (name.isNotEmpty && !advanced.contains(name)) name,
  ];
  final groups = [
    for (final name in primary)
      if (!Profile.systemPolicyTargets.contains(name)) name,
  ];
  final policies = [
    for (final name in primary)
      if (Profile.systemPolicyTargets.contains(name)) name,
  ];

  String? subtitleOf(String name) {
    if (subtitles.containsKey(name)) return subtitles[name];
    if (advanced.contains(name)) return kAdvancedBuiltinNotes[name] ?? '高级内置';
    if (Profile.builtinTargets.contains(name)) return '系统策略';
    return null;
  }

  Widget chipOf(String name) =>
      NameChip(name: name, subtitle: subtitleOf(name));

  SectionedPickerItem<String> itemOf(String name) => SectionedPickerItem(
    value: name,
    chip: chipOf(name),
    searchText: name,
    selected: name == current,
  );

  return showSectionedPicker<String>(
    context,
    title: title,
    subtitle: subtitle,
    searchHint: '搜索目标组或节点',
    emptyHint: '没有匹配的目标',
    sections: [
      if (emptyLabel != null)
        SectionedPickerSection<String>(
          items: [
            SectionedPickerItem(
              value: '',
              chip: Text(emptyLabel, style: hintStyle(context)),
              searchText: emptyLabel,
              selected: current.isEmpty,
            ),
          ],
        ),
      // 顺序固定：策略组 -> 系统策略 -> 高级内置（折叠头在行之上、默认收起）。
      if (groups.isNotEmpty)
        SectionedPickerSection<String>(
          label: '策略组',
          items: [for (final name in groups) itemOf(name)],
        ),
      if (policies.isNotEmpty)
        SectionedPickerSection<String>(
          label: '系统策略',
          items: [for (final name in policies) itemOf(name)],
        ),
      if (advanced.isNotEmpty)
        SectionedPickerSection<String>(
          collapsible: true,
          collapsedLabel: '高级内置（不常用）',
          expandedLabel: '收起高级内置',
          items: [for (final name in advanced) itemOf(name)],
        ),
    ],
  );
}
