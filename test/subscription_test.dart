import 'dart:convert';
import 'dart:io';

import 'package:clashdeck/core/parse/subscription.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const _vless =
    'vless://b831381d-6324-4d53-ad4f-8cda48b30811@hk.example.com:443'
    '?encryption=none&security=tls&sni=cdn.example.com&type=ws&path=%2Fws#香港 01';
const _trojan = 'trojan://pass@us.example.com:443?sni=us.example.com#美国 01';
const _hy2 = 'hysteria2://pw@tw.example.com:8443?sni=tw.example.com#台湾 01';

String _b64(String text) => base64Encode(utf8.encode(text));

void main() {
  group('parseSubscriptionBody', () {
    test('明文多行链接', () {
      final r = parseSubscriptionBody('$_vless\n$_trojan\n$_hy2');
      expect(r.count, 3);
      expect(r.proxies.map((p) => p['type']), ['vless', 'trojan', 'hysteria2']);
      expect(r.yamlConfig, isNull);
    });

    test('base64 打包（机场最常见）', () {
      final r = parseSubscriptionBody(_b64('$_vless\n$_trojan'));
      expect(r.count, 2);
      expect(r.proxies.first['name'], '香港 01');
    });

    test('无 padding 的 base64url 也能解', () {
      final raw = _b64('$_vless\n$_trojan').replaceAll('=', '');
      final urlSafe = raw.replaceAll('+', '-').replaceAll('/', '_');
      final r = parseSubscriptionBody(urlSafe);
      expect(r.count, 2);
    });

    test('Clash YAML 订阅：节点取出来，原文保留', () {
      const yaml = '''
proxies:
  - name: 香港 01
    type: vless
    server: hk.example.com
    port: 443
    uuid: b831381d-6324-4d53-ad4f-8cda48b30811
  - name: 美国 01
    type: trojan
    server: us.example.com
    port: 443
    password: pass

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - 香港 01
''';
      final r = parseSubscriptionBody(yaml, title: '我的机场');
      expect(r.count, 2);
      expect(r.yamlConfig, isNotNull);
      expect(r.title, '我的机场');
    });

    test('空内容 / 垃圾内容会抛 ConfigEditException', () {
      expect(
        () => parseSubscriptionBody('   '),
        throwsA(isA<ConfigEditException>()),
      );
      expect(
        () => parseSubscriptionBody('hello world 这不是订阅'),
        throwsA(isA<ConfigEditException>()),
      );
    });
  });

  group('SubscriptionUsage', () {
    test('解析 subscription-userinfo 并格式化', () {
      final usage = SubscriptionUsage.parse(
        'upload=0; download=1073741824; total=107374182400; expire=1790000000',
      );
      expect(usage, isNotNull);
      expect(usage!.used, 1073741824);
      expect(usage.total, 107374182400);
      expect(usage.label, contains('已用 1.0 GB / 共 100 GB'));
      expect(usage.label, contains('到期 2026-'));
    });

    test('缺字段/全是垃圾时返回 null 或省略那一句', () {
      expect(SubscriptionUsage.parse(null), isNull);
      expect(SubscriptionUsage.parse('nonsense'), isNull);
      final onlyTotal = SubscriptionUsage.parse('total=1048576');
      expect(onlyTotal!.used, isNull);
      expect(onlyTotal.label, '总流量 1.0 MB');
    });
  });

  group('fetchSubscription（本地假服务器）', () {
    late HttpServer server;
    late String base;

    setUp(() async {
      server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      base = 'http://127.0.0.1:${server.port}';
      server.listen((req) async {
        final res = req.response;
        if (req.uri.path == '/sub') {
          res.headers.set('profile-title', 'base64:${_b64('演示机场')}');
          res.headers.set(
            'subscription-userinfo',
            'upload=0; download=2048; total=1048576; expire=1790000000',
          );
          res.headers.contentType = ContentType.text;
          res.write(_b64('$_vless\n$_trojan\n$_hy2'));
        } else if (req.uri.path == '/missing') {
          res.statusCode = 404;
          res.write('not found');
        } else {
          res.write('garbage');
        }
        await res.close();
      });
    });

    tearDown(() async => server.close(force: true));

    test('拉取 → 解析节点、标题、用量', () async {
      final result = await fetchSubscription('$base/sub');
      expect(result.count, 3);
      expect(result.title, '演示机场');
      expect(result.usage!.total, 1048576);
    });

    test('非 2xx 抛 ConfigEditException', () async {
      await expectLater(
        fetchSubscription('$base/missing'),
        throwsA(isA<ConfigEditException>()),
      );
    });

    test('不是 http(s) 地址直接拒', () async {
      await expectLater(
        fetchSubscription('vless://whatever'),
        throwsA(isA<ConfigEditException>()),
      );
    });
  });
}
