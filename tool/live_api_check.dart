// 对着 WSL 里真实运行的 mihomo 校验 Dart 侧 REST 客户端。
// 前置：wsl-start-core.sh 已把内核起在 127.0.0.1:9090，secret=test-secret。
// 用法：dart run tool/live_api_check.dart
import 'dart:io';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/mihomo_api.dart';
import 'package:clashdeck/runtime/runtime_config.dart';

Future<void> main() async {
  final api = MihomoApi(port: 9090, secret: 'test-secret');
  var failures = 0;

  void check(String label, Object? value) {
    stdout.writeln('  $label = $value');
  }

  void expectTrue(String label, bool ok) {
    stdout.writeln('${ok ? 'PASS' : 'FAIL'}  $label');
    if (!ok) failures++;
  }

  try {
    final version = await api.version();
    check('version', version);
    expectTrue('/version 返回 meta 字段', version['meta'] == true);
    expectTrue('ping()', await api.ping());

    final proxies = await api.proxies();
    check('proxies keys', proxies.keys.toList());
    expectTrue('/proxies 含 PROXY 组', proxies.containsKey('PROXY'));

    final map = await api.proxyMap();
    check('proxyMap keys', map.keys.toList());
    expectTrue('proxyMap 已剥壳（无 proxies 键）', !map.containsKey('proxies'));

    final rules = await api.rules();
    check('rules count', rules.length);
    expectTrue('/rules 有 2 条', rules.length == 2);

    final configs = await api.configs();
    check('configs.mode', configs['mode']);
    expectTrue('/configs 读到 mode=rule', configs['mode'] == 'rule');

    await api.setMode('global');
    expectTrue('PATCH mode=global', (await api.configs())['mode'] == 'global');
    await api.setMode('rule');

    await api.selectProxy('PROXY', 'DIRECT');
    final Object? selected = (await api.proxyMap())['PROXY'];
    check('PROXY.now', selected is Map ? selected['now'] : selected);
    expectTrue(
      '切换选中节点',
      selected is Map<Object?, Object?> && selected['now'] == 'DIRECT',
    );

    // 热重载：把运行配置原样推回去，内核应保持存活（listener 复用）。
    final sample = File(r'D:\dev\_downloads\runtime-check.yaml');
    final text = sample.existsSync()
        ? sample.readAsStringSync()
        : RuntimeConfig.buildRuntimeYaml(
            YamlDoc.parse('mode: rule\n'),
            tunFileDescriptor: 0,
            secret: 'test-secret',
          );
    await api.loadPayload(text);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    expectTrue('PUT /configs payload 后内核仍在线', await api.ping());
  } catch (e, st) {
    stdout.writeln('FAIL  异常：$e');
    stdout.writeln(st);
    failures++;
  } finally {
    api.close();
  }

  stdout.writeln(failures == 0 ? '\nALL PASS' : '\n$failures FAILURES');
  exit(failures == 0 ? 0 : 1);
}
