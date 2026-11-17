import 'dart:async';
import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../core/edit/geosite_index.dart';
import '../core/edit/rule_presets.dart';
import 'dropdown.dart';
import 'theme.dart';
import 'widgets.dart';

/// GEO 选择结果：选中的 code 与要写进规则的目标组。
class GeoPick {
  const GeoPick({required this.code, required this.target});

  final String code;
  final String target;
}

/// 打开 GEO 选择器，返回用户选的 code 与目标组；取消返回 null。
///
/// 搜索按 geosite code 与中文名匹配，输入没有命中时允许直接把输入当 code 用
/// （geo 索引偶尔滞后于内核，手输兜底比报错更实用）。
Future<GeoPick?> showGeositePicker(
  BuildContext context, {
  required List<String> groupNames,
}) {
  return showAppDialog<GeoPick>(
    context,
    builder: (_) => _GeositePickerDialog(groupNames: groupNames),
  );
}

class _GeositePickerDialog extends StatefulWidget {
  const _GeositePickerDialog({required this.groupNames});

  final List<String> groupNames;

  @override
  State<_GeositePickerDialog> createState() => _GeositePickerDialogState();
}

class _GeositePickerDialogState extends State<_GeositePickerDialog> {
  final TextEditingController _ctrl = TextEditingController();
  List<GeositeEntry> _all = const [];
  bool _loading = true;
  String? _code;
  String _target = '';

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final entries = await loadGeositeIndex();
    if (!mounted) return;
    setState(() {
      _all = entries;
      _loading = false;
      // 默认选中常用分类里的第一个，而不是字母表最前面的 `0x0`。
      final curated = entries.where((e) => kGeositeLabels.containsKey(e.code));
      _code ??= curated.isEmpty ? null : curated.first.code;
    });
  }

  String get _query => _ctrl.text.trim().toLowerCase();

  /// 默认只列「有中文名」的常用分类：直接按字母表取前 40 个会全是
  /// `0x0`、`1337x` 这种看不出含义的 code，用户会以为是错数据。
  List<GeositeEntry> get _curated => [
    for (final entry in _all)
      if (kGeositeLabels.containsKey(entry.code)) entry,
  ];

  List<GeositeEntry> get _matches {
    final q = _query;
    if (q.isEmpty) return _curated.take(40).toList();
    final hits = <GeositeEntry>[];
    for (final entry in _all) {
      final label = geositeLabelOf(entry.code).toLowerCase();
      if (entry.code.contains(q) || label.contains(q)) {
        hits.add(entry);
        if (hits.length >= 40) break;
      }
    }
    return hits;
  }

  String get _finalTarget => _target.isEmpty
      ? sanitizeGroupName(geositeLabelOf(_code ?? ''))
      : _target;

  void _submit() {
    final code = _code;
    if (code == null || code.isEmpty) return;
    Navigator.of(context).pop(GeoPick(code: code, target: _finalTarget));
  }

  @override
  Widget build(BuildContext context) {
    final matches = _matches;
    final q = _query;
    final useCustom =
        q.isNotEmpty && matches.isEmpty && RegExp(r'^[a-z0-9-]+$').hasMatch(q);
    return AlertDialog(
      title: const Text('添加 GEO 规则'),
      content: SizedBox(
        width: math.min(480, MediaQuery.sizeOf(context).width - 48),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _ctrl,
              autofocus: false,
              decoration: const InputDecoration(
                labelText: '搜索',
                hintText: 'code 或中文名，例如 netflix',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: Insets.sm),
            SizedBox(
              height: 220,
              child: _loading
                  ? Center(
                      child: Text('正在读取 geo 索引…', style: hintStyle(context)),
                    )
                  : ListView(
                      children: [
                        for (final entry in matches)
                          ListTile(
                            dense: true,
                            selected: entry.code == _code,
                            title: Text(
                              entry.code,
                              style: monoStyle(context, size: 12),
                            ),
                            subtitle: Text(
                              geositeLabelOf(entry.code),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            onTap: () => setState(() => _code = entry.code),
                          ),
                        if (useCustom)
                          ListTile(
                            dense: true,
                            selected: _code == q,
                            leading: const Icon(Icons.edit_outlined, size: 18),
                            title: Text('直接使用：$q', style: hintStyle(context)),
                            onTap: () => setState(() => _code = q),
                          ),
                        if (matches.isEmpty && !useCustom)
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              vertical: Insets.md,
                            ),
                            child: Text(
                              '没有匹配的 code',
                              style: hintStyle(context),
                            ),
                          ),
                      ],
                    ),
            ),
            const SizedBox(height: Insets.sm),
            Row(
              children: [
                Text('目标组', style: hintStyle(context)),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: AppDropdown<String>(
                    compact: true,
                    value: _target,
                    options: [
                      const DropdownOption('', '新建同名组'),
                      for (final name in widget.groupNames)
                        DropdownOption(name, name),
                    ],
                    onChanged: (v) => setState(() => _target = v),
                  ),
                ),
              ],
            ),
            const SizedBox(height: Insets.xs),
            Text(
              '实际写入：GEOSITE,${_code ?? ''},$_finalTarget',
              style: hintStyle(context),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: _code == null ? null : _submit,
          child: const Text('添加'),
        ),
      ],
    );
  }
}
