// 生成一份"运行配置"样本，用来在 PC 上用 mihomo -t 校验格式。
// 用法：dart run tool/export_runtime.dart > /tmp/runtime-check.yaml
import 'dart:io';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_config.dart';

const _userConfig = '''
# 用户配置：注释要保留，但运行配置是派生文件
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
proxies:
  - name: Test-SS
    type: ss
    server: 127.0.0.1
    port: 8388
    cipher: aes-128-gcm
    password: test
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - Test-SS
      - DIRECT
rules:
  - DOMAIN-SUFFIX,example.com,PROXY
  - MATCH,PROXY
''';

void main(List<String> args) {
  final fd = args.isNotEmpty ? int.tryParse(args.first) ?? 0 : 0;
  final doc = YamlDoc.parse(_userConfig);
  final out = RuntimeConfig.buildRuntimeYaml(
    doc,
    tunFileDescriptor: fd,
    controller: '127.0.0.1:9090',
    secret: 'test-secret',
  );
  stdout.write(out);
  if (!out.endsWith('\n')) stdout.write('\n');
}
