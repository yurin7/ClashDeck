import 'proxy_schema.dart';

/// 所有协议 schema 里出现过的键（fields + nested）。
///
/// 用来区分「这是别的协议的键」和「schema 之外用户自己写的自由字段」：
/// 前者切换协议时该删，后者必须原样保留。
final Set<String> allSchemaKeys = {
  for (final schema in kProxySchemas) ...[
    for (final f in schema.fields) f.key,
    for (final m in schema.nested) m.key,
  ],
};

/// 切换协议类型时，把不属于新协议的键丢掉。
///
/// 否则从 vless 表单切到 vmess 再保存，会把 `reality-opts` 这类只属于旧协议的
/// 键写进 YAML——内核遇到不认识的键会直接报错，或者更糟：静默忽略，让人以为
/// 配置生效了。
///
/// 保留 `name` / `type`，以及 [allSchemaKeys] 之外的自由字段
/// （例如用户手写的 `dialer-proxy`、`smux`）。返回被删掉的键名，方便提示。
List<String> pruneValuesToSchema(
  String type,
  Map<String, Object?> values, {
  Set<String>? foreignKeys,
}) {
  final schema = proxySchemaFor(type);
  if (schema == null) return const [];
  final allowed = <String>{
    for (final f in schema.fields) f.key,
    for (final m in schema.nested) m.key,
  }..addAll(const ['name', 'type']);

  final foreign = foreignKeys ?? allSchemaKeys;
  final removed = <String>[];
  for (final key in values.keys.toList()) {
    if (allowed.contains(key)) continue;
    if (!foreign.contains(key)) continue; // schema 之外的自由字段，保留
    values.remove(key);
    removed.add(key);
  }
  return removed;
}

/// schema 里该协议支持的键（含 name/type）。
Set<String> schemaKeysFor(String type) {
  final schema = proxySchemaFor(type);
  if (schema == null) return const {};
  return {
    for (final f in schema.fields) f.key,
    for (final m in schema.nested) m.key,
  };
}
