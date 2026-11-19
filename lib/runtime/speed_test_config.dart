import '../core/edit/config_ops.dart';
import '../core/yaml/yaml_doc.dart';
import 'runtime_config.dart';

/// 临时测速内核里承载目标节点的 selector 名称。
const String kSpeedProbeGroup = 'speed-probe';

/// 生成测速用的最小配置解析失败。
class SpeedTestConfigException implements Exception {
  const SpeedTestConfigException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 生成只服务一次下载测速的最小配置。
///
/// 与用户配置无关：只拷贝目标节点、建一个只含它的 selector，再用
/// `MATCH` 全部走它。这样节点不需要出现在任何策略组里，也不会改动用户
/// 的真实配置（`dns` 关闭、日志静默，减少干扰）。
String buildSpeedTestConfig(YamlDoc doc, {required String nodeName}) {
  if (!doc.isValid) {
    throw const SpeedTestConfigException('配置解析失败，无法测速');
  }
  final rawProxies = doc.plainAt(['proxies']);
  if (rawProxies is! List || rawProxies.isEmpty) {
    throw const SpeedTestConfigException('配置里还没有节点');
  }
  Map<String, Object?>? target;
  for (final entry in rawProxies) {
    if (entry is! Map) continue;
    final name = entry['name'];
    if (name is String && name == nodeName) {
      target = <String, Object?>{
        for (final e in entry.entries)
          if (e.key is String) e.key as String: e.value,
      };
      break;
    }
  }
  if (target == null) {
    throw SpeedTestConfigException('找不到节点：$nodeName');
  }
  var next = YamlDoc.parse('{}');
  next = ConfigOps.setTop(next, 'mixed-port', RuntimeConfig.proxyPortFor(doc));
  next = ConfigOps.setTop(next, 'log-level', 'silent');
  next = ConfigOps.setTop(next, 'proxies', [target]);
  next = ConfigOps.setTop(next, 'proxy-groups', [
    <String, Object?>{
      'name': kSpeedProbeGroup,
      'type': 'select',
      'proxies': <String>[nodeName],
    },
  ]);
  next = ConfigOps.setTop(next, 'rules', ['MATCH,$kSpeedProbeGroup']);
  next = ConfigOps.setTop(next, 'dns', <String, Object?>{'enable': false});
  if (!next.isValid) {
    throw const SpeedTestConfigException('测速配置生成失败');
  }
  return next.text;
}
