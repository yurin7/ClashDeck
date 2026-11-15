// 端到端管线自检：分享链接 → YAML（无损编辑）→ 运行配置 → 交给真实内核验证。
//
// 这个测试会把最终运行配置写到系统临时目录的 clashdeck-pipeline.yaml，
// 之后可以用 WSL 里的真 mihomo 跑 `-t` 检查内核是否接受：
//   wsl -d Ubuntu-24.04 -- /tmp/mihomo -t -d /tmp/mihomo-home -f /mnt/d/dev/_downloads/pipeline.yaml
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/validate/validator.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_config.dart';
import 'package:clashdeck/ui/home_page.dart';

const _links = '''
# 一份混合订阅：不同协议 + 注释 + 空行，验证导入器的健壮性
vless://11111111-2222-3333-4444-555555555555@example.com:443?encryption=none&security=tls&sni=cdn.example.com&type=ws&host=cdn.example.com&path=%2Fws#%E9%A6%99%E6%B8%AF%20WS

vless://aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee@1.2.3.4:8443?encryption=none&security=reality&sni=www.microsoft.com&fp=chrome&pbk=FTDk1NU3V-JYLfsG7qbrxa86b7eSc-RduMaGrKosUBg&sid=abcd&type=tcp&flow=xtls-rprx-vision#%E6%97%A5%E6%9C%AC%20Reality

trojan://pa%24%24word@trojan.example.org:443?security=tls&sni=trojan.example.org&type=grpc&serviceName=gun&allowInsecure=1#%E6%96%B0%E5%8A%A0%E5%9D%A1%20gRPC

ss://YWVzLTI1Ni1nY206cGFzc3dvcmQ@ss.example.net:8388#%E7%BE%8E%E5%9B%BD%20SS
''';

void main() {
  test('链接 → YAML → 运行配置，整条链路自洽且被校验器接受', () {
    final yaml = buildConfigFromText(_links, name: '管线自检');
    final doc = YamlDoc.parse(yaml);

    // 1. 四个节点都进来了，且组里有它们
    final profile = Profile.from(doc);
    expect(profile.proxies, hasLength(4));
    expect(
      profile.proxies.map((p) => p.name),
      containsAll(['香港 WS', '日本 Reality', '新加坡 gRPC', '美国 SS']),
    );
    final group = profile.groups.single;
    expect(
      group.members,
      containsAll(['香港 WS', '日本 Reality', '新加坡 gRPC', '美国 SS']),
    );

    // 2. 较难的嵌套字段真的落到了 YAML 里
    final hk = profile.proxyByName['香港 WS']!;
    expect(hk.type, 'vless');
    final ws = hk.raw['ws-opts'] as Map;
    expect(ws['path'], '/ws');
    expect(ws['headers'], {'Host': 'cdn.example.com'});

    final jp = profile.proxyByName['日本 Reality']!;
    final reality = jp.raw['reality-opts'] as Map;
    expect(
      '${reality['public-key']}',
      'FTDk1NU3V-JYLfsG7qbrxa86b7eSc-RduMaGrKosUBg',
    );
    expect('${reality['short-id']}', 'abcd');
    expect('${jp.raw['client-fingerprint']}', 'chrome');
    expect('${jp.raw['flow']}', 'xtls-rprx-vision');

    final sg = profile.proxyByName['新加坡 gRPC']!;
    expect('${(sg.raw['grpc-opts'] as Map)['grpc-service-name']}', 'gun');
    expect(sg.raw['skip-cert-verify'], isTrue);

    // 3. 校验器不报错（warning 允许）
    final report = ConfigValidator.validate(doc);
    expect(
      report.hasErrors,
      isFalse,
      reason: report.errors.map((i) => i.message).join('; '),
    );

    // 4. 生成运行配置：带 tun fd + dns 段
    final runtime = RuntimeConfig.buildRuntimeYaml(
      doc,
      tunFileDescriptor: 12,
      secret: 'pipeline-secret',
    );
    expect(runtime, contains('file-descriptor: 12'));
    expect(runtime, contains('enhanced-mode: fake-ip'));
    expect(runtime, contains('proxy-groups:'));
    expect(runtime, contains('name: 香港 WS'));

    // 5. 落盘给真内核做 `-t` 校验
    final out = File(
      '${Directory.systemTemp.path}${Platform.pathSeparator}clashdeck-pipeline.yaml',
    );
    out.writeAsStringSync(runtime);
    // ignore: avoid_print
    print('运行配置已写入：${out.path}');
  });

  test('运行配置保留用户注释与顶层顺序', () {
    final yaml = buildConfigFromText(_links, name: '注释检查');
    final runtime = RuntimeConfig.buildRuntimeYaml(
      YamlDoc.parse(yaml),
      tunFileDescriptor: 0,
    );
    expect(runtime, contains('ClashDeck'));
    expect(runtime.indexOf('mixed-port'), lessThan(runtime.indexOf('proxies:')));
  });
}
