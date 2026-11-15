import 'field_spec.dart';

/// mihomo 代理分组的类型（与 YAML 里 `type` 的取值一致）。
const List<String> kGroupTypes = <String>[
  'select',
  'url-test',
  'fallback',
  'load-balance',
  'relay',
];

/// 代理分组的全部字段（mihomo v1.19.34）。
///
/// 这里覆盖的是 `proxy-groups` 数组里单个分组的键；`name` / `type`
/// 为必填，其余按分组类型可选。
const List<FieldSpec> kGroupSchema = <FieldSpec>[
  FieldSpec(
    key: 'name',
    labelZh: '分组名称',
    kind: FieldKind.string,
    group: FieldGroup.basic,
    required: true,
    help: '配置内唯一，规则与其它分组按此名称引用',
  ),
  FieldSpec(
    key: 'type',
    labelZh: '分组类型',
    kind: FieldKind.enumChoice,
    group: FieldGroup.basic,
    options: kGroupTypes,
    defaultValue: 'select',
    required: true,
    help: 'select 手动选择；其余为自动测速/负载均衡',
  ),
  FieldSpec(
    key: 'proxies',
    labelZh: '成员节点',
    kind: FieldKind.stringList,
    group: FieldGroup.basic,
    help: '显式列出的节点或分组名称',
  ),
  FieldSpec(
    key: 'use',
    labelZh: '使用订阅',
    kind: FieldKind.stringList,
    group: FieldGroup.basic,
    help: '按订阅（provider）名称引用其中的全部节点',
  ),
  FieldSpec(
    key: 'url',
    labelZh: '测速地址',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '健康检查地址，如 http://www.gstatic.com/generate_204',
  ),
  FieldSpec(
    key: 'interval',
    labelZh: '测速间隔',
    kind: FieldKind.durationSeconds,
    group: FieldGroup.protocol,
    defaultValue: 300,
    help: '单位：秒',
  ),
  FieldSpec(
    key: 'timeout',
    labelZh: '测速超时',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '单位：毫秒',
  ),
  FieldSpec(
    key: 'max-failed-times',
    labelZh: '最大失败次数',
    kind: FieldKind.int,
    group: FieldGroup.advanced,
    advanced: true,
    help: '连续失败多少次后判定节点不可用',
  ),
  FieldSpec(
    key: 'empty-fallback',
    labelZh: '空回退',
    kind: FieldKind.string,
    group: FieldGroup.advanced,
    advanced: true,
    help: '成员全部不可用时的回退目标，如 DIRECT',
  ),
  FieldSpec(
    key: 'lazy',
    labelZh: '懒加载',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    defaultValue: true,
    help: '仅在被使用时才测速，省电',
  ),
  FieldSpec(
    key: 'disable-udp',
    labelZh: '禁用 UDP',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '该分组不转发 UDP 流量',
  ),
  FieldSpec(
    key: 'filter',
    labelZh: '节点过滤',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '正则表达式，仅保留匹配的节点',
  ),
  FieldSpec(
    key: 'exclude-filter',
    labelZh: '排除过滤',
    kind: FieldKind.string,
    group: FieldGroup.protocol,
    help: '正则表达式，排除匹配的节点',
  ),
  FieldSpec(
    key: 'exclude-type',
    labelZh: '排除类型',
    kind: FieldKind.string,
    group: FieldGroup.advanced,
    advanced: true,
    help: '按协议类型排除，如 ss|vmess',
  ),
  FieldSpec(
    key: 'expected-status',
    labelZh: '期望状态码',
    kind: FieldKind.stringList,
    group: FieldGroup.advanced,
    advanced: true,
    help: '如 204, 200；留空接受 2xx/3xx',
  ),
  FieldSpec(
    key: 'include-all',
    labelZh: '包含全部节点',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '自动纳入配置里的所有节点',
  ),
  FieldSpec(
    key: 'include-all-proxies',
    labelZh: '包含全部代理',
    kind: FieldKind.bool,
    group: FieldGroup.protocol,
    help: '自动纳入所有代理（含订阅）',
  ),
  FieldSpec(
    key: 'include-all-providers',
    labelZh: '包含全部订阅',
    kind: FieldKind.bool,
    group: FieldGroup.advanced,
    advanced: true,
    help: '自动纳入所有订阅里的节点',
  ),
  FieldSpec(
    key: 'hidden',
    labelZh: '隐藏',
    kind: FieldKind.bool,
    group: FieldGroup.advanced,
    advanced: true,
    help: '在界面上隐藏该分组',
  ),
  FieldSpec(
    key: 'icon',
    labelZh: '图标',
    kind: FieldKind.string,
    group: FieldGroup.basic,
    help: '图标 URL 或内置图标名',
  ),
];

/// 该分组是否使用"自动成员"（而不是显式 `proxies` 列表）。
///
/// 只要出现 `include-all` / `include-all-proxies` / `filter` /
/// `exclude-filter` 任一键，UI 就应展示"自动成员"模式，隐藏手动成员选择。
bool groupUsesComputedMembers(Map<String, Object?> group) {
  return group.containsKey('include-all') ||
      group.containsKey('include-all-proxies') ||
      group.containsKey('filter') ||
      group.containsKey('exclude-filter');
}
