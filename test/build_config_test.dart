import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/validate/validator.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/home_page.dart';

void main() {
  group('buildConfigFromText：整段 YAML', () {
    test('以注释开头的内容按 YAML 原样返回', () {
      const text = '''
# 我的配置
mixed-port: 7890
proxies: []
rules:
  - MATCH,DIRECT
''';
      final out = buildConfigFromText(text);
      expect(out, text.trim());
    });

    test('YAML 里的 URL 不会被当成分享链接', () {
      const text = 'note: see https://example.com\nproxies: []\n';
      expect(buildConfigFromText(text), text.trim());
    });

    test('YAML 语法错误抛 ConfigEditException', () {
      expect(
        () => buildConfigFromText('proxies: [\n  - {name: a\n'),
        throwsA(isA<ConfigEditException>()),
      );
    });
  });

  group('buildConfigFromText：分享链接', () {
    const vlessLink =
        'vless://11111111-2222-3333-4444-555555555555@example.com:443'
        '?encryption=none&security=tls&sni=cdn.example.com&type=ws&path=%2Fws'
        '&host=cdn.example.com&fp=chrome&flow=xtls-rprx-vision#'
        '%E9%A6%99%E6%B8%AF%2001';

    test('单条 vless 链接生成可用配置（含 proxies: [] 空列表追加）', () {
      final out = buildConfigFromText(vlessLink);
      final doc = YamlDoc.parse(out);
      expect(doc.isValid, isTrue);
      final profile = Profile.from(doc);

      expect(profile.proxies, hasLength(1));
      final node = profile.proxies.single;
      expect(node.name, '香港 01');
      expect(node.type, 'vless');
      expect(node.server, 'example.com');
      expect(node.port, 443);
      expect(node['uuid'], '11111111-2222-3333-4444-555555555555');
      expect(node.raw['tls'], isTrue);
      expect(node.raw['port'], 443);
      expect(node['servername'], 'cdn.example.com');
      expect(node['flow'], 'xtls-rprx-vision');
      final ws = node.raw['ws-opts'] as Map<String, Object?>;
      expect(ws['path'], '/ws');
      expect(
        (ws['headers'] as Map<String, Object?>)['Host'],
        'cdn.example.com',
      );

      // 节点被加入了默认组，且空 flow 列表已被展开成块状列表。
      final group = profile.groupByName[kDefaultGroupName]!;
      expect(group.members, ['DIRECT', 'REJECT', '香港 01']);
      expect(out.contains('proxies: []'), isFalse);
      // 风格：必须是块状列表，不能是 flow 风格 `proxies: [{...}]`。
      expect(out.contains('proxies: ['), isFalse);
      expect(out.contains('  - name: 香港 01'), isTrue);
      expect(out.contains('    ws-opts:\n      path: /ws'), isTrue);

      // 生成的配置自身必须能通过校验（只有"空 select 组"之类的警告不算错误）。
      final report = ConfigValidator.validate(doc);
      expect(
        report.errors,
        isEmpty,
        reason: report.errors.map((e) => e.message).join('; '),
      );
    });

    test('多条链接 + 注释 + 垃圾行：只保留合法节点且按原名去重', () {
      const text =
          '''
# 订阅
$vlessLink
not a link
vless://aaaa-bbbb@example.com:443?security=tls&sni=a.com#%E9%A6%99%E6%B8%AF%2001
''';
      final out = buildConfigFromText(text);
      final profile = Profile.from(YamlDoc.parse(out));
      expect(profile.proxies, hasLength(2));
      expect(profile.proxies.map((p) => p.name), ['香港 01', '香港 01-2']);
      expect(profile.groupByName[kDefaultGroupName]!.members, [
        'DIRECT',
        'REJECT',
        '香港 01',
        '香港 01-2',
      ]);
    });

    test('trojan 与 ss 链接混排', () {
      const text =
          'trojan://pass@t.example.com:443?sni=t.example.com#T1\n'
          'ss://YWVzLTI1Ni1nY206cGFzcw@1.2.3.4:8388#S1';
      final profile = Profile.from(YamlDoc.parse(buildConfigFromText(text)));
      expect(profile.proxies.map((p) => p.type), ['trojan', 'ss']);
      expect(profile.proxies.map((p) => p.name), ['T1', 'S1']);
    });

    test('纯垃圾文本抛 ConfigEditException', () {
      expect(
        () => buildConfigFromText('hello world'),
        throwsA(isA<ConfigEditException>()),
      );
    });
  });

  group('starterConfig', () {
    test('空配置本身可解析且能通过校验', () {
      final doc = YamlDoc.parse(
        // 直接构造一个与 starterConfig 等价的空配置（避免依赖 path_provider）。
        '''
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
dns:
  enable: true
  enhanced-mode: fake-ip
  nameserver:
    - 223.5.5.5
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT
rules:
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
''',
      );
      expect(doc.isValid, isTrue);
      final report = ConfigValidator.validate(doc);
      expect(report.errors, isEmpty);
    });
  });
}
