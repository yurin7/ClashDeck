import 'package:material_ui/material_ui.dart';
import 'package:yaml/yaml.dart';

import '../core/schema/field_spec.dart';
import '../core/schema/proxy_schema.dart';
import '../core/schema/schema_prune.dart';
import 'dropdown.dart';
import 'fields.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/edit_dialog.dart';

/// 新增/编辑一个节点。表单完全由 [kProxySchemas] 驱动，
/// schema 没覆盖到的字段会落在「其它字段」里，保证任何 mihomo 字段都能手改。
///
/// 返回 `Map<String, Object?>?`（null 表示取消）。
class NodeFormPage extends StatefulWidget {
  const NodeFormPage({
    super.key,
    this.initial,
    this.existingNames = const [],
    this.title,
    this.onDelete,
  });

  /// 编辑已有节点时传入（含未知字段）。
  final Map<String, Object?>? initial;

  /// 已存在的节点名（用于重名检查）。
  final List<String> existingNames;

  final String? title;

  /// 提供则 AppBar 显示删除按钮（手机上没有右键菜单，删除只能从这里进）。
  /// 由调用方负责真正的删除与错误提示；返回后本页自己关闭。
  final Future<void> Function()? onDelete;

  @override
  State<NodeFormPage> createState() => _NodeFormPageState();
}

class _NodeFormPageState extends State<NodeFormPage> {
  late String _type;
  late Map<String, Object?> _values;
  final Map<String, TextEditingController> _ctrls = {};
  final Map<String, FocusNode> _focus = {};
  String? _error;

  @override
  void initState() {
    super.initState();
    _values = Map<String, Object?>.from(widget.initial ?? const {});
    final rawType = _values['type'];
    _type = rawType is String && proxySchemaFor(rawType) != null
        ? rawType
        : kSupportedProxyTypes.first;
    _values['type'] = _type;
    if (widget.initial == null) {
      _values.putIfAbsent('port', () => 443);
    }
  }

  @override
  void dispose() {
    for (final c in _ctrls.values) {
      c.dispose();
    }
    for (final f in _focus.values) {
      f.dispose();
    }
    super.dispose();
  }

  ProxySchema get _schema => proxySchemaFor(_type)!;

  // -------------------------------------------------------------- 文本缓存

  TextEditingController _controller(String cacheKey, String initialText) =>
      _ctrls.putIfAbsent(
        cacheKey,
        () => TextEditingController(text: initialText),
      );

  FocusNode _focusNode(String cacheKey) =>
      _focus.putIfAbsent(cacheKey, FocusNode.new);

  static String displayText(Object? value) {
    if (value == null) return '';
    if (value is bool) return value ? 'true' : 'false';
    if (value is List) return value.join(', ');
    if (value is Map) return '';
    return '$value';
  }

  static Object? parseText(FieldSpec spec, String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    switch (spec.kind) {
      case FieldKind.int:
      case FieldKind.durationSeconds:
        return int.tryParse(t) ?? t;
      case FieldKind.bool:
        final lower = t.toLowerCase();
        if (lower == 'true' || lower == '1' || lower == 'yes') return true;
        if (lower == 'false' || lower == '0' || lower == 'no') return false;
        return t;
      case FieldKind.stringList:
        return t
            .split(',')
            .map((e) => e.trim())
            .where((e) => e.isNotEmpty)
            .toList();
      case FieldKind.enumChoice:
      case FieldKind.string:
      case FieldKind.portRange:
      case FieldKind.map:
        return t;
    }
  }

  // -------------------------------------------------------------- 写值

  void _set(FieldSpec spec, String text) {
    final v = parseText(spec, text);
    setState(() {
      if (v == null) {
        _values.remove(spec.key);
      } else {
        _values[spec.key] = v;
      }
      // 依赖字段变化可能让别的字段显隐，清掉 error 提示
      _error = null;
    });
  }

  void _setNested(MapSchema map, FieldSpec spec, String text) {
    final v = parseText(spec, text);
    final current = Map<String, Object?>.from(
      (_values[map.key] as Map?)?.cast<String, Object?>() ?? const {},
    );
    if (v == null) {
      current.remove(spec.key);
    } else {
      current[spec.key] = v;
    }
    setState(() {
      if (current.isEmpty) {
        _values.remove(map.key);
      } else {
        _values[map.key] = current;
      }
    });
  }

  void _toggleNested(MapSchema map, bool on) {
    setState(() {
      if (on) {
        final defaults = <String, Object?>{};
        for (final f in map.fields) {
          if (f.defaultValue != null) defaults[f.key] = f.defaultValue;
        }
        _values[map.key] = defaults;
      } else {
        _values.remove(map.key);
      }
    });
  }

  bool _visible(FieldSpec spec, Map<String, Object?> scope) {
    if (!spec.hasCondition) return true;
    final cond = scope[spec.visibleWhenKey];
    // 布尔型依赖：true/false 双向都要能匹配
    if (spec.visibleWhenValue is bool && cond is bool) {
      return cond == spec.visibleWhenValue;
    }
    if (cond == null) return false;
    return '$cond' == '${spec.visibleWhenValue}';
  }

  // -------------------------------------------------------------- 保存

  Future<void> _confirmDelete() async {
    final onDelete = widget.onDelete;
    if (onDelete == null) return;
    final name = '${widget.initial?['name'] ?? ''}';
    final ok = await showConfirmDialog(
      context,
      title: '删除节点「$name」？',
      message: '会同时从所有策略组里移除它，这个操作可以撤销。',
      confirmLabel: '删除',
      danger: true,
    );
    if (ok != true) return;
    await onDelete();
    if (mounted) Navigator.of(context).pop();
  }

  void _submit() {
    final name = '${_values['name'] ?? ''}'.trim();
    if (name.isEmpty) {
      setState(() => _error = '请填写节点名称');
      return;
    }
    if (widget.existingNames.contains(name) &&
        name != '${widget.initial?['name'] ?? ''}') {
      setState(() => _error = '节点名「$name」已存在');
      return;
    }
    for (final spec in _schema.fields) {
      if (!spec.required) continue;
      final v = _values[spec.key];
      if (v == null || '$v'.trim().isEmpty) {
        setState(() => _error = '请填写「${spec.labelZh}」');
        return;
      }
    }
    // 丢掉空字符串，保留 false/0
    final raw = <String, Object?>{};
    _values.forEach((k, v) {
      if (v == null) return;
      if (v is String && v.trim().isEmpty) return;
      raw[k] = v;
    });
    raw['type'] = _type;
    Navigator.of(context).pop(_ordered(raw));
  }

  /// 统一的键顺序：先 name/type/server/port/uuid……，再按 schema 字段顺序，
  /// 最后是 schema 之外的手写字段。
  ///
  /// 不排的话 YAML 里会写成 `type: vless / port: 443 / name: n1`（表单的插入
  /// 顺序），虽然内核不在乎，但人读配置时第一行看不到名字很难受。
  static Map<String, Object?> _ordered(Map<String, Object?> values) {
    const priority = <String>[
      'name',
      'type',
      'server',
      'port',
      'uuid',
      'password',
      'cipher',
      'flow',
      'network',
      'tls',
      'sni',
      'servername',
      'udp',
    ];
    final out = <String, Object?>{};
    for (final key in priority) {
      final v = values[key];
      if (v != null) out[key] = v;
    }
    final schema = proxySchemaFor('${values['type'] ?? ''}');
    if (schema != null) {
      for (final spec in schema.fields) {
        if (out.containsKey(spec.key)) continue;
        final v = values[spec.key];
        if (v != null) out[spec.key] = v;
      }
      for (final map in schema.nested) {
        if (out.containsKey(map.key)) continue;
        final v = values[map.key];
        if (v != null) out[map.key] = v;
      }
    }
    for (final entry in values.entries) {
      out.putIfAbsent(entry.key, () => entry.value);
    }
    return out;
  }

  // -------------------------------------------------------------- UI

  @override
  Widget build(BuildContext context) {
    final schema = _schema;
    final known = <String>{
      ...schema.fields.map((e) => e.key),
      ...schema.nested.map((e) => e.key),
      'type',
    };
    final extra = <String, Object?>{
      for (final e in _values.entries)
        if (!known.contains(e.key)) e.key: e.value,
    };

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title ?? (widget.initial == null ? '添加节点' : '编辑节点')),
        actions: [
          if (widget.onDelete != null)
            IconButton(
              tooltip: '删除节点',
              icon: const Icon(Icons.delete_outline),
              onPressed: _confirmDelete,
            ),
          TextButton(onPressed: _submit, child: const Text('保存')),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Insets.lg, Insets.sm, Insets.lg, 96),
        children: [
          if (_error != null)
            Padding(
              padding: const EdgeInsets.only(bottom: Insets.sm),
              child: _Banner(
                text: _error!,
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          AppDropdown<String>(
            label: '协议类型',
            icon: Icons.alt_route,
            expand: true,
            value: _type,
            options: [
              for (final t in kSupportedProxyTypes)
                DropdownOption(t, '${proxySchemaFor(t)?.labelZh ?? t}（$t）'),
            ],
            onChanged: (t) {
              if (t == _type) return;
              setState(() {
                _type = t;
                _values['type'] = t;
                // 旧协议专有的键不能带进新协议的表单
                pruneValuesToSchema(t, _values);
                _error = null;
              });
            },
          ),
          for (final group in FieldGroup.values) ...[
            if (schema.fields.any((f) => f.group == group))
              _SectionTitle(
                title: switch (group) {
                  FieldGroup.basic => '基础',
                  FieldGroup.tls => 'TLS / 加密',
                  FieldGroup.transport => '传输',
                  FieldGroup.protocol => '协议参数',
                  FieldGroup.advanced => '其它',
                },
              ),
            for (final spec in schema.fields)
              if (spec.group == group &&
                  // 「类型」由上面那张卡片负责，这里不再重复渲染一个下拉
                  spec.key != 'type' &&
                  _visible(spec, _values))
                _fieldRow(
                  spec,
                  _values,
                  (text) => _set(spec, text),
                  cacheKey: spec.key,
                ),
          ],
          if (schema.nested.isNotEmpty) const _SectionTitle(title: '传输细节'),
          for (final map in schema.nested) _nestedBlock(map),
          if (extra.isNotEmpty || true) ...[
            const _SectionTitle(title: '其它字段'),
            ..._extraRows(extra, schema),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _addExtraField,
                icon: const Icon(Icons.add),
                label: const Text('添加字段'),
              ),
            ),
          ],
          // 删除入口放在表单底部，比 AppBar 里的小图标更容易找到。
          if (widget.onDelete != null) ...[
            const SizedBox(height: Insets.md),
            const Hairline(),
            const SizedBox(height: Insets.sm),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: _confirmDelete,
                style: TextButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                ),
                icon: const Icon(Icons.delete_outline),
                label: const Text('删除这个节点'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _fieldRow(
    FieldSpec spec,
    Map<String, Object?> scope,
    void Function(String) onChanged, {
    required String cacheKey,
  }) {
    final key = cacheKey;
    final current = scope[spec.key];
    switch (spec.kind) {
      case FieldKind.bool:
        final value = current == true;
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(spec.labelZh),
          subtitle: spec.help == null ? null : Text(spec.help!),
          value: value,
          onChanged: (v) {
            setState(() {
              if (v) {
                scope[spec.key] = true;
              } else {
                scope.remove(spec.key);
              }
              _error = null;
            });
          },
        );
      case FieldKind.enumChoice:
        // schema 里少数枚举把空串当成「可选空」（例如 vless.flow、ss.plugin），
        // 而空串已经由上面的「（默认）」项表示——不去掉会变成两个同值选项，
        // DropdownButton 会直接抛断言。
        final options = (spec.options ?? const <String>[])
            .where((o) => o.isNotEmpty)
            .toList(growable: false);
        final raw = current == null ? '' : '$current';
        // 配置里可能存在 schema 枚举没收录的值（内核比 schema 跑得快），
        // 必须原样显示出来，否则用户一保存就把原值丢了。
        final hasRaw = raw.isNotEmpty && !options.contains(raw);
        final value = hasRaw ? raw : raw;
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppDropdown<String>(
            label: spec.labelZh,
            helper: spec.help,
            expand: true,
            value: value,
            options: [
              const DropdownOption<String>('', '（默认）'),
              for (final o in options) DropdownOption<String>(o, o),
              // 配置里可能存在 schema 枚举没收录的值（内核比 schema 跑得快）。
              if (hasRaw) DropdownOption<String>(raw, '$raw（当前值，schema 未收录）'),
            ],
            onChanged: (v) {
              if (v.isEmpty) {
                setState(() => scope.remove(spec.key));
              } else {
                onChanged(v);
              }
            },
          ),
        );
      default:
        final controller = _controller(key, displayText(current));
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: AppTextField(
            controller: controller,
            focusNode: _focusNode(key),
            keyboardType: switch (spec.kind) {
              FieldKind.int ||
              FieldKind.durationSeconds => TextInputType.number,
              _ => TextInputType.text,
            },
            obscureText: spec.secret,
            decoration: fieldDecoration(
              label: spec.labelZh,
              helper: spec.help,
              hint: spec.defaultValue == null
                  ? null
                  : '默认 ${displayText(spec.defaultValue)}',
            ),
            onChanged: onChanged,
          ),
        );
    }
  }

  Widget _nestedBlock(MapSchema map) {
    final enabled = _values[map.key] is Map;
    final nestedValues =
        ((_values[map.key] as Map?)?.cast<String, Object?>() ??
        const <String, Object?>{});
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: ExpansionTile(
        title: Text(map.labelZh),
        subtitle: Text(
          enabled ? '已启用' : '未启用',
          style: Theme.of(context).textTheme.bodySmall,
        ),
        trailing: Switch(
          value: enabled,
          onChanged: (v) => _toggleNested(map, v),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
        children: enabled
            ? [
                for (final spec in map.fields)
                  if (_visible(spec, nestedValues))
                    _fieldRow(
                      spec,
                      nestedValues,
                      (text) => _setNested(map, spec, text),
                      cacheKey: '${map.key}.${spec.key}',
                    ),
              ]
            : [
                ListTile(
                  dense: true,
                  title: Text(
                    '打开开关后填写该传输的参数',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
      ),
    );
  }

  List<Widget> _extraRows(Map<String, Object?> extra, ProxySchema schema) {
    final rows = <Widget>[];
    extra.forEach((k, v) {
      final spec = FieldSpec(
        key: k,
        labelZh: k,
        kind: v is bool
            ? FieldKind.bool
            : v is int
            ? FieldKind.int
            : v is List
            ? FieldKind.stringList
            : FieldKind.string,
        group: FieldGroup.advanced,
      );
      rows.add(
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _fieldRow(spec, _values, (text) {
                final parsed = parseText(spec, text);
                setState(() {
                  if (parsed == null) {
                    _values.remove(k);
                  } else {
                    _values[k] = parsed;
                  }
                });
              }, cacheKey: 'extra.$k'),
            ),
            IconButton(
              tooltip: '删除字段 $k',
              onPressed: () => setState(() {
                _values.remove(k);
                _ctrls.remove('extra.$k')?.dispose();
              }),
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      );
    });
    if (rows.isEmpty) {
      rows.add(
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Text(
            '没有额外字段；需要时手动添加（值按 YAML 解析）',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
      );
    }
    return rows;
  }

  Future<void> _addExtraField() async {
    final keyCtrl = TextEditingController();
    final valueCtrl = TextEditingController();
    final result = await showAppDialog<MapEntry<String, Object?>?>(
      context,
      width: dialogWidthOf(context),
      builder: (ctx) => EditDialog(
        title: '添加字段',
        confirmLabel: '添加',
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppTextField(controller: keyCtrl, label: '键（YAML 名）'),
            const SizedBox(height: 12),
            AppTextField(
              controller: valueCtrl,
              label: '值（按 YAML 解析：true / 123 / [a, b] / {}）',
            ),
          ],
        ),
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () {
          final k = keyCtrl.text.trim();
          if (k.isEmpty) return;
          Navigator.pop(ctx, MapEntry(k, _parseYamlValue(valueCtrl.text)));
        },
      ),
    );
    disposeAfterDialog(keyCtrl);
    disposeAfterDialog(valueCtrl);
    if (result == null) return;
    setState(() {
      _values[result.key] = result.value;
      _ctrls.remove('extra.${result.key}');
    });
  }

  static Object? _parseYamlValue(String text) {
    final t = text.trim();
    if (t.isEmpty) return null;
    try {
      final v = loadYaml('v: ${t.replaceAll('\n', '\n  ')}');
      if (v is Map) return v['v'];
    } catch (_) {
      // 解析失败就当字符串
    }
    return t;
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle({required this.title});
  final String title;

  static IconData _iconFor(String title) => switch (title) {
    '基础' => Icons.badge_outlined,
    'TLS / 加密' => Icons.lock_outline,
    '传输' => Icons.swap_horiz,
    '传输细节' => Icons.settings_ethernet,
    '协议参数' => Icons.tune,
    '其它' => Icons.more_horiz,
    _ => Icons.notes_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.xs,
        Insets.xl,
        Insets.xs,
        Insets.sm,
      ),
      child: Row(
        children: [
          Container(width: 2, height: 12, color: scheme.primary),
          const SizedBox(width: Insets.sm),
          Icon(_iconFor(title), size: 16, color: scheme.primary),
          const SizedBox(width: 6),
          Text(
            title,
            style: microStyle(context).copyWith(color: scheme.onSurface),
          ),
        ],
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.text, required this.color});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.12),
      borderRadius: BorderRadius.circular(8),
    ),
    child: Text(text, style: TextStyle(color: color)),
  );
}
