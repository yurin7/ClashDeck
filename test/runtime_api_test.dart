import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/mihomo_api.dart';
import 'package:clashdeck/runtime/runtime_config.dart';

typedef _Req = ({String method, String path, String? auth, String body});

void main() {
  group('MihomoApi', () {
    late HttpServer server;
    late MihomoApi api;
    final requests = <_Req>[];

    setUp(() async {
      requests.clear();
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        final body = await utf8.decoder.bind(req).join();
        requests.add((
          method: req.method,
          path: req.uri.path,
          auth: req.headers.value('authorization'),
          body: body,
        ));
        final res = req.response;
        final path = req.uri.path;
        if (path == '/version') {
          res.headers.contentType = ContentType.json;
          res.write('{"version":"v1.19.34","meta":true}');
        } else if (path == '/proxies') {
          res.headers.contentType = ContentType.json;
          res.write(
            '{"proxies":{'
            '"GLOBAL":{"type":"Selector","now":"DIRECT","all":["DIRECT"]},'
            '"PROXY":{"type":"Selector","now":"A","all":["A","B"]}}}',
          );
        } else if (path == '/proxies/A/delay') {
          res.write('{"delay":123}');
        } else if (path == '/rules') {
          res.write(
            '{"rules":[{"type":"MATCH","payload":"","proxy":"PROXY"}]}',
          );
        } else if (path == '/configs' && req.method == 'PUT') {
          res.statusCode = HttpStatus.noContent;
        } else if (path == '/configs' && req.method == 'PATCH') {
          res.statusCode = HttpStatus.noContent;
        } else if (path == '/traffic') {
          res.write('{"up":10,"down":20}\n{"up":1,"down":2}\n');
        } else if (path == '/missing') {
          res.statusCode = HttpStatus.notFound;
          res.write('{"message":"not found"}');
        } else {
          res.statusCode = HttpStatus.noContent;
        }
        await res.close();
      });
      api = MihomoApi(host: '127.0.0.1', port: server.port, secret: 's3cret');
    });

    tearDown(() async {
      api.close();
      await server.close(force: true);
    });

    test('version 携带 Bearer secret', () async {
      final v = await api.version();
      expect(v['version'], 'v1.19.34');
      expect(v['meta'], isTrue);
      expect(requests.single.method, 'GET');
      expect(requests.single.path, '/version');
      expect(requests.single.auth, 'Bearer s3cret');
      expect(await api.ping(), isTrue);
    });

    test('reloadConfig 用 PUT /configs?force=true 和空 path/payload', () async {
      await api.reloadConfig();
      final req = requests.single;
      expect(req.method, 'PUT');
      expect(req.path, '/configs');
      expect(jsonDecode(req.body), {'path': '', 'payload': ''});
    });

    test('selectProxy 对组名做 URL 编码', () async {
      await api.selectProxy('GROUP A', '香港 01');
      final req = requests.single;
      expect(req.method, 'PUT');
      expect(req.path, '/proxies/GROUP%20A'); // Dart 的 Uri.path 保留百分号编码
      expect(jsonDecode(req.body), {'name': '香港 01'});
    });

    test('proxyMap 展开成 Map<String, Map>', () async {
      final map = await api.proxyMap();
      expect(map.keys, containsAll(['GLOBAL', 'PROXY']));
      expect(map['PROXY']!['now'], 'A');
      expect((map['PROXY']!['all'] as List), ['A', 'B']);
    });

    test('proxies 已剥掉内核的 proxies 外壳', () async {
      final map = await api.proxies();
      expect(map.keys, isNot(contains('proxies')));
      expect(map.keys, containsAll(['GLOBAL', 'PROXY']));
      expect((map['PROXY']! as Map)['type'], 'Selector');
    });

    test('delay 返回毫秒数', () async {
      expect(await api.delay('A'), 123);
    });

    test('rules 取出列表', () async {
      final rules = await api.rules();
      expect(rules, hasLength(1));
      expect((rules.single as Map)['type'], 'MATCH');
    });

    test('patchConfigs 用 PATCH 发 body', () async {
      await api.setMode('global');
      expect(requests.single.method, 'PATCH');
      expect(jsonDecode(requests.single.body), {'mode': 'global'});
    });

    test('流式 traffic 按行解析', () async {
      final events = await api.traffic().toList();
      expect(events, hasLength(2));
      expect(events.first.up, 10);
      expect(events.first.down, 20);
      expect(events.last.up, 1);
    });
  });

  group('MihomoApi 错误处理', () {
    test('非 2xx 抛 MihomoApiException', () async {
      final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      server.listen((req) async {
        req.response.statusCode = HttpStatus.notFound;
        req.response.write('{"message":"not found"}');
        await req.response.close();
      });
      final api = MihomoApi(host: '127.0.0.1', port: server.port);
      await expectLater(
        api.version(),
        throwsA(
          isA<MihomoApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            404,
          ),
        ),
      );
      // ping 把异常吞掉，返回 false。
      expect(await api.ping(), isFalse);
      api.close();
      await server.close(force: true);
    });
  });

  group('RuntimeConfig', () {
    const userYaml = '''
# 用户自己的配置，注释要保留
mixed-port: 7890
log-level: debug
proxies:
  - name: A
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - A
rules:
  - MATCH,PROXY
''';

    test('写入 tun.file-descriptor 与 external-controller，注释保留', () {
      final out = RuntimeConfig.buildRuntimeYaml(
        YamlDoc.parse(userYaml),
        tunFileDescriptor: 42,
        secret: 'abc',
      );
      final doc = YamlDoc.parse(out);
      expect(doc.isValid, isTrue);
      final root = doc.plainRoot;
      expect(root['external-controller'], '127.0.0.1:9090');
      expect(root['secret'], 'abc');
      expect(root['mixed-port'], 7890); // 用户已有值不动
      expect(root['log-level'], 'debug'); // 也不被覆盖
      final tun = root['tun'] as Map<String, Object?>;
      expect(tun['enable'], isTrue);
      expect(tun['file-descriptor'], 42);
      expect(tun['auto-route'], isFalse);
      expect(tun['stack'], 'gvisor');
      final dns = root['dns'] as Map<String, Object?>;
      expect(dns['enable'], isTrue);
      expect(dns['enhanced-mode'], 'fake-ip');
      expect(out.contains('# 用户自己的配置，注释要保留'), isTrue);
      // 块状风格，不是 flow。
      expect(out.contains('tun: {'), isFalse);
      expect(out.contains('  file-descriptor: 42'), isTrue);
    });

    test('用户写的栈会保留；v4 地址由内核从 fake-ip-range 推导，不再写进配置', () {
      const src = '''
mixed-port: 7890
tun:
  stack: system
  mtu: 1500
''';
      final out = RuntimeConfig.buildRuntimeYaml(
        YamlDoc.parse(src),
        tunFileDescriptor: 9,
      );
      final tun = YamlDoc.parse(out).plainAt(['tun'])! as Map;
      expect(tun['stack'], 'system');
      expect(tun['mtu'], 1500); // MTU 仍然尊重用户
      expect(tun['file-descriptor'], 9);
      // mihomo 的 parseTun() 会忽略 inet4-address，一律用 fake-ip-range 截 /30，
      // 所以这里不写；网卡地址改由 tunAddressFor() 交给 Kotlin 建网卡。
      expect(tun['inet4-address'], isNull);
      expect(tun['inet6-address'], isNull);
    });

    test('tunAddressFor 跟着 fake-ip-range 走，与内核推导结果一致', () {
      expect(
        RuntimeConfig.tunAddressFor(YamlDoc.parse('mixed-port: 7890')),
        '198.18.0.1/30',
      );
      expect(
        RuntimeConfig.tunAddressFor(
          YamlDoc.parse('dns:\n  fake-ip-range: 198.19.0.1/16\n'),
        ),
        '198.19.0.1/30',
      );
      expect(
        RuntimeConfig.tunAddressFor(
          YamlDoc.parse('dns:\n  enhanced-mode: redir-host\n'),
        ),
        '198.18.0.1/30',
      );
    });

    test('堆栈缺省是 gvisor，ipv6 打开时补 v6 地址', () {
      const src = '''
mixed-port: 7890
ipv6: true
''';
      final out = RuntimeConfig.buildRuntimeYaml(
        YamlDoc.parse(src),
        tunFileDescriptor: 9,
      );
      final tun = YamlDoc.parse(out).plainAt(['tun'])! as Map;
      expect(tun['stack'], 'gvisor');
      expect(tun['inet4-address'], isNull);
      expect(tun['inet6-address'], ['fdfe:dcba:9876::1/126']);
    });

    test('fd=0（仅代理端口模式）显式关闭 tun', () {
      final out = RuntimeConfig.buildRuntimeYaml(
        YamlDoc.parse(userYaml),
        tunFileDescriptor: 0,
      );
      final tun = YamlDoc.parse(out).plainAt(['tun']);
      expect(tun, isA<Map>());
      expect((tun! as Map)['enable'], isFalse);
    });

    test('已有 dns 段的用户设置不被覆盖，只补缺', () {
      const src = '''
dns:
  enable: false
  nameserver:
    - 1.1.1.1
rules:
  - MATCH,DIRECT
''';
      final out = RuntimeConfig.buildRuntimeYaml(
        YamlDoc.parse(src),
        tunFileDescriptor: 3,
      );
      final dns = YamlDoc.parse(out).plainRoot['dns'] as Map<String, Object?>;
      expect(dns['enable'], isFalse); // 尊重用户
      expect(dns['nameserver'], ['1.1.1.1']);
      expect(dns['enhanced-mode'], 'fake-ip'); // 补上缺失的
    });

    test('重复生成同样输入得到同样文本（幂等）', () {
      final once = RuntimeConfig.buildRuntimeYaml(
        YamlDoc.parse(userYaml),
        tunFileDescriptor: 5,
        secret: 'x',
      );
      final twice = RuntimeConfig.buildRuntimeYaml(
        YamlDoc.parse(once),
        tunFileDescriptor: 5,
        secret: 'x',
      );
      expect(twice, once);
    });
  });
}
