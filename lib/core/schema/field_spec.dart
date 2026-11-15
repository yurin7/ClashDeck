/// 单个节点 / 分组的字段描述，用于驱动动态表单、默认值与配置校验。
///
/// 本文件保持纯 Dart（不依赖 Flutter），可被 `core` 下任意层与单测直接引用。
library;

/// 字段的取值类型。
///
/// [durationSeconds] 表示"以秒为单位的整数"（表单里仍按整数编辑，
/// 写回 YAML 时会写成整数秒）；[portRange] 表示端口或端口段表达式，
/// 例如 `1000-2000`、`1000,2000-3000`。
enum FieldKind {
  string,
  int,
  bool,
  enumChoice,
  stringList,
  map,
  durationSeconds,
  portRange,
}

/// 字段在动态表单中的所属分组（对应 UI 上的分区标题）。
enum FieldGroup { basic, tls, transport, protocol, advanced }

/// 一个字段的声明。
///
/// 除了 [key] / [labelZh] / [kind] / [group] 之外都可选，
/// 默认值语义保持与 mihomo 一致：不填 [defaultValue] 表示交给内核默认值。
class FieldSpec {
  const FieldSpec({
    required this.key,
    required this.labelZh,
    required this.kind,
    required this.group,
    this.options,
    this.defaultValue,
    this.help,
    this.required = false,
    this.advanced = false,
    this.secret = false,
    this.visibleWhenKey,
    this.visibleWhenValue,
  });

  /// 与 YAML 键名完全一致，例如 `skip-cert-verify`。
  final String key;

  /// 面向普通用户的中文标签。
  final String labelZh;

  final FieldKind kind;

  /// 该字段在动态表单中的分区。
  final FieldGroup group;

  /// [kind] 为 [FieldKind.enumChoice] 时的可选值（YAML 中实际写入的值）。
  final List<String>? options;

  /// 新建条目时的初始值；`null` 表示不预填。
  final Object? defaultValue;

  /// 一行中文提示，展示在输入框下方。
  final String? help;

  /// 是否必填（用于表单校验与配置体检）。
  final bool required;

  /// 是否收进"高级"折叠区。
  final bool advanced;

  /// 密码 / 私钥类字段，UI 需要掩码显示。
  final bool secret;

  /// 条件显示的依赖字段 key（例如 `tls`、`network`）。
  final String? visibleWhenKey;

  /// 依赖字段等于该值时显示；与 [visibleWhenKey] 成对使用。
  final Object? visibleWhenValue;

  /// 是否存在条件显示规则。
  bool get hasCondition => visibleWhenKey != null;

  /// 在依赖字段取 [conditionValue] 时，本字段是否应该显示。
  bool isVisibleFor(Object? conditionValue) =>
      visibleWhenKey == null || conditionValue == visibleWhenValue;
}
