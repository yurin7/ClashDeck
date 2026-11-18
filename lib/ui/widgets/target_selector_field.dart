import 'package:material_ui/material_ui.dart';

import '../../core/edit/rule_targets.dart';
import '../../core/model/profile.dart';
import '../chips.dart';
import '../fields.dart';
import '../sheets/picker_sheet.dart';
import '../theme.dart';
import 'select_sheet.dart';

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
    final scheme = Theme.of(context).colorScheme;
    final showEmpty = value.isEmpty && emptyLabel != null;
    return InkWell(
      borderRadius: BorderRadius.circular(Radiuses.md),
      onTap: enabled && onChanged != null ? () => _open(context) : null,
      child: InputDecorator(
        decoration: fieldDecoration(label: label, enabled: enabled),
        child: Row(
          children: [
            Expanded(
              child: showEmpty
                  ? Text(emptyLabel!, style: hintStyle(context))
                  : Align(
                      alignment: Alignment.centerLeft,
                      child: NameChip(name: value),
                    ),
            ),
            Icon(Icons.expand_more, size: 18, color: scheme.onSurfaceVariant),
          ],
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
  return showSelectSheet<String>(
    context,
    title: title,
    subtitle: subtitle,
    body: (_) => _TargetPickerSheet(
      options: options,
      otherOptions: otherOptions,
      current: current,
      emptyLabel: emptyLabel,
      subtitles: subtitles,
    ),
  );
}

class _TargetPickerSheet extends StatefulWidget {
  const _TargetPickerSheet({
    required this.options,
    required this.otherOptions,
    required this.current,
    this.emptyLabel,
    this.subtitles = const <String, String?>{},
  });

  final List<String> options;
  final List<String> otherOptions;
  final String current;
  final String? emptyLabel;

  /// 调用方额外补充的副标题（例如策略组的「组 · 3」）。
  final Map<String, String?> subtitles;

  @override
  State<_TargetPickerSheet> createState() => _TargetPickerSheetState();
}

class _TargetPickerSheetState extends State<_TargetPickerSheet> {
  bool _showAdvanced = false;

  Widget _chip(String name) => NameChip(
    name: name,
    subtitle: widget.subtitles.containsKey(name)
        ? widget.subtitles[name]
        : widget.otherOptions.contains(name)
        ? kAdvancedBuiltinNotes[name] ?? '高级内置'
        : Profile.builtinTargets.contains(name)
        ? '系统策略'
        : null,
  );

  @override
  Widget build(BuildContext context) {
    final primary = [
      for (final name in widget.options)
        if (name.isNotEmpty && !widget.otherOptions.contains(name))
          PickerSheetRow(
            searchText: name,
            title: _chip(name),
            selected: name == widget.current,
            onTap: () => Navigator.of(context).pop(name),
          ),
    ];
    final rows = <PickerSheetRow>[
      if (widget.emptyLabel != null)
        PickerSheetRow(
          searchText: widget.emptyLabel!,
          title: Text(widget.emptyLabel!, style: hintStyle(context)),
          selected: widget.current.isEmpty,
          onTap: () => Navigator.of(context).pop(''),
        ),
      ...primary,
      if (_showAdvanced)
        for (final name in widget.otherOptions)
          PickerSheetRow(
            searchText: name,
            title: _chip(name),
            selected: name == widget.current,
            onTap: () => Navigator.of(context).pop(name),
          ),
    ];
    return PickerSheetScaffold(
      searchHint: '搜索目标组或节点',
      toolbar: false,
      sections: [PickerSheetSection(rows: rows)],
      selectedCount: widget.current.isEmpty ? 0 : 1,
      onSelectAll: () {},
      onInvert: () {},
      onClear: () {},
      emptyHint: '没有匹配的目标',
      footer: Row(
        children: [
          if (widget.otherOptions.isNotEmpty)
            TextButton.icon(
              onPressed: () => setState(() => _showAdvanced = !_showAdvanced),
              icon: Icon(
                _showAdvanced ? Icons.expand_less : Icons.expand_more,
                size: 18,
              ),
              label: Text(
                _showAdvanced
                    ? '收起高级内置'
                    : '高级内置（${widget.otherOptions.length}）',
              ),
            ),
          const Spacer(),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('取消'),
          ),
        ],
      ),
    );
  }
}
