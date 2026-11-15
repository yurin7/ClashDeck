// Unit tests for the share-link -> mihomo proxy parser.
//
// Run: flutter test test/parse_test.dart

import 'dart:convert';

import 'package:clashdeck/core/parse/share_link.dart';
import 'package:flutter_test/flutter_test.dart';

/// Builds a `vmess://` link by base64-encoding [payload] as JSON.
String vmessLink(Map<String, Object?> payload) {
  return 'vmess://${base64.encode(utf8.encode(jsonEncode(payload)))}';
}

void main() {
  group('supportedSchemes', () {
    test('exposes the schemes the UI should offer', () {
      expect(supportedSchemes, <String>[
        'vless',
        'vmess',
        'trojan',
        'ss',
        'ssr',
        'hysteria2',
        'hy2',
        'tuic',
        'socks5',
        'socks',
        'http',
      ]);
      expect(kUriSchemes, supportedSchemes);
    });
  });

  group('vless', () {
    test('vless + reality maps reality-opts, fingerprint and tls', () {
      const String link = 'vless://8f7b4c1e-91a2-4d3e-8f45-0123456789ab'
          '@203.0.113.10:443'
          '?type=tcp&security=reality&sni=www.microsoft.com&fp=chrome'
          '&pbk=Z84J2IelR9Z3Ct9Q8m3S8l8u9z0Jx7y6W5v4U3t2S1r&sid=ab12'
          '&flow=xtls-rprx-vision&encryption=none'
          '#%E9%A6%99%E6%B8%AF01';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], '香港01');
      expect(node['type'], 'vless');
      expect(node['server'], '203.0.113.10');
      expect(node['port'], 443);
      expect(node['port'], isA<int>());
      expect(node['uuid'], '8f7b4c1e-91a2-4d3e-8f45-0123456789ab');
      expect(node['network'], 'tcp');
      expect(node['udp'], true);
      expect(node['tls'], true);
      expect(node['servername'], 'www.microsoft.com');
      expect(node['client-fingerprint'], 'chrome');
      expect(node['flow'], 'xtls-rprx-vision');
      expect(node['encryption'], 'none');
      expect(node['reality-opts'], <String, Object?>{
        'public-key': 'Z84J2IelR9Z3Ct9Q8m3S8l8u9z0Jx7y6W5v4U3t2S1r',
        'short-id': 'ab12',
      });
      expect(node.containsKey('skip-cert-verify'), isFalse);
    });

    test('vless + ws exposes path and Host header', () {
      const String link = 'vless://11111111-2222-3333-4444-555555555555'
          '@hk.example.com:443'
          '?type=ws&security=tls&sni=hk.example.com&path=%2Fws'
          '&host=cdn.example.com&fp=chrome#HK-WS';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['network'], 'ws');
      expect(node['tls'], true);
      expect(node['flow'], isNull);
      final Map<String, Object?> ws =
          node['ws-opts']! as Map<String, Object?>;
      expect(ws['path'], '/ws');
      final Map<String, Object?> headers =
          ws['headers']! as Map<String, Object?>;
      expect(headers['Host'], 'cdn.example.com');
      expect(node.containsKey('reality-opts'), isFalse);
    });

    test('vless + ws defaults the path to / when the link has none', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@a.example.com:443'
        '?type=ws&security=tls#NOPATH',
      );
      expect(node, isNotNull);
      final Map<String, Object?> ws =
          node!['ws-opts']! as Map<String, Object?>;
      expect(ws['path'], '/');
      expect(ws.containsKey('headers'), isFalse);
    });

    test('vless + ws maps early data to mihomo ws-opts', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@a.example.com:443'
        '?type=ws&security=tls&path=%2Fed&host=ed.example.com'
        '&ed=2048&eh=X-Early-Data#ED',
      );
      expect(node, isNotNull);
      final Map<String, Object?> ws =
          node!['ws-opts']! as Map<String, Object?>;
      expect(ws['max-early-data'], 2048);
      expect(ws['early-data-header-name'], 'X-Early-Data');
    });

    test('vless + grpc maps grpc-service-name', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@g.example.com:443'
        '?type=grpc&security=tls&sni=g.example.com'
        '&serviceName=grpc-svc&mode=gun#GRPC',
      );
      expect(node, isNotNull);
      expect(node!['network'], 'grpc');
      expect(node['grpc-opts'], <String, Object?>{
        'grpc-service-name': 'grpc-svc',
        'grpc-mode': 'gun',
      });
    });

    test('vless + http maps path/Host as string lists', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@h.example.com:443'
        '?type=http&security=tls&path=%2Fa%2C%2Fb'
        '&host=a.com%2Cb.com#HTTP',
      );
      expect(node, isNotNull);
      expect(node!['network'], 'http');
      expect(node['http-opts'], <String, Object?>{
        'path': <String>['/a', '/b'],
        'headers': <String, Object?>{
          'Host': <String>['a.com', 'b.com'],
        },
      });
    });

    test('vless + h2 maps h2-opts', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@h2.example.com:443'
        '?type=h2&security=tls&path=%2Fh2&host=h2.example.com#H2',
      );
      expect(node, isNotNull);
      expect(node!['network'], 'h2');
      expect(node['h2-opts'], <String, Object?>{
        'host': <String>['h2.example.com'],
        'path': '/h2',
      });
    });

    test('vless + httpupgrade reuses ws-opts and sets v2ray-http-upgrade', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@u.example.com:443'
        '?type=httpupgrade&security=tls&path=%2Fup&host=up.example.com#UP',
      );
      expect(node, isNotNull);
      expect(node!['network'], 'httpupgrade');
      final Map<String, Object?> ws =
          node['ws-opts']! as Map<String, Object?>;
      expect(ws['path'], '/up');
      expect(ws['v2ray-http-upgrade'], true);
      final Map<String, Object?> headers =
          ws['headers']! as Map<String, Object?>;
      expect(headers['Host'], 'up.example.com');
    });

    test('vless + alpn / insecure / security=none', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@n.example.com:80'
        '?type=tcp&security=none&sni=n.example.com&allowInsecure=1'
        '&alpn=h2%2Chttp%2F1.1#NONE',
      );
      expect(node, isNotNull);
      expect(node!['tls'], false);
      expect(node['alpn'], <String>['h2', 'http/1.1']);
      expect(node['skip-cert-verify'], true);
      // servername is only emitted for TLS transports.
      expect(node.containsKey('servername'), isFalse);
      expect(node.containsKey('encryption'), isFalse);
    });

    test('vless name is URL-decoded from the fragment', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@a.example.com:443'
        '?security=tls#%E9%A6%99%E6%B8%AF01',
      );
      expect(node, isNotNull);
      expect(node!['name'], '香港01');
    });

    test('vless accepts a raw (unencoded) CJK fragment', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@a.example.com:443'
        '?security=tls#东京 02',
      );
      expect(node, isNotNull);
      expect(node!['name'], '东京 02');
    });

    test('vless reality without pbk keeps tls but omits broken reality-opts',
        () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@a.example.com:443'
        '?security=reality&sni=a.example.com&sid=ab12#NOPBK',
      );
      expect(node, isNotNull);
      expect(node!['tls'], true);
      expect(node['reality-opts'], isNull);
    });

    test('vless treats xtls security as TLS', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@x.example.com:443'
        '?security=xtls&sni=x.example.com&flow=xtls-rprx-vision#XTLS',
      );
      expect(node, isNotNull);
      expect(node!['tls'], true);
      expect(node['servername'], 'x.example.com');
      expect(node['flow'], 'xtls-rprx-vision');
    });

    test('vless falls back to host:port when the fragment is empty', () {
      final Map<String, Object?>? node = parseShareLink(
        'vless://11111111-2222-3333-4444-555555555555@fallback.example.com:8443'
        '?security=tls',
      );
      expect(node, isNotNull);
      expect(node!['name'], 'fallback.example.com:8443');
    });
  });

  group('vmess', () {
    test('vmess base64 JSON (ws + tls + aid 0)', () {
      const String link = 'vmess://eyJ2IjoiMiIsInBzIjoidm1lc3Mtd3MiLCJhZGQiOiJ2Mi5leGFtcGxlLmNvbSIsInBvcnQiOiI0NDMiLCJpZCI6ImI4MzEzODFkLTYzMjQtNGQ1My1hZDRmLThjZGE0OGIzMDgxMSIsImFpZCI6IjAiLCJzY3kiOiJhdXRvIiwibmV0Ijoid3MiLCJ0eXBlIjoibm9uZSIsImhvc3QiOiJjZG4uZXhhbXBsZS5jb20iLCJwYXRoIjoiL3ZtIiwidGxzIjoidGxzIiwic25pIjoidjIuZXhhbXBsZS5jb20ifQ==';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], 'vmess-ws');
      expect(node['type'], 'vmess');
      expect(node['server'], 'v2.example.com');
      expect(node['port'], 443);
      expect(node['port'], isA<int>());
      expect(node['uuid'], 'b831381d-6324-4d53-ad4f-8cda48b30811');
      expect(node['alterId'], 0);
      expect(node['alterId'], isA<int>());
      expect(node['cipher'], 'auto');
      expect(node['network'], 'ws');
      expect(node['udp'], true);
      expect(node['tls'], true);
      expect(node['servername'], 'v2.example.com');
      final Map<String, Object?> ws =
          node['ws-opts']! as Map<String, Object?>;
      expect(ws['path'], '/vm');
      final Map<String, Object?> headers =
          ws['headers']! as Map<String, Object?>;
      expect(headers['Host'], 'cdn.example.com');
    });

    test('vmess accepts unpadded base64url', () {
      final Map<String, Object?> payload = <String, Object?>{
        'v': '2',
        'ps': 'urlsafe-vmess',
        'add': 'u.example.com',
        'port': '8443',
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'aid': '0',
        'scy': 'aes-128-gcm',
        'net': 'ws',
        'path': '/u',
        'host': 'u.example.com',
        'tls': 'tls',
        'sni': 'u.example.com',
      };
      final String padded =
          base64.encode(utf8.encode(jsonEncode(payload)));
      final String urlsafe = padded
          .replaceAll('=', '')
          .replaceAll('+', '-')
          .replaceAll('/', '_');
      expect(urlsafe.contains('='), isFalse);
      final Map<String, Object?>? node =
          parseShareLink('vmess://$urlsafe');
      expect(node, isNotNull);
      expect(node!['name'], 'urlsafe-vmess');
      expect(node['port'], 8443);
      expect(node['cipher'], 'aes-128-gcm');
      final Map<String, Object?> ws =
          node['ws-opts']! as Map<String, Object?>;
      expect(ws['path'], '/u');
    });

    test('vmess accepts the base64url alphabet (- and _)', () {
      // The display name `~~~` makes the standard encoding contain a `+`,
      // which is rewritten into the URL-safe `-` / `_` alphabet.
      final Map<String, Object?> payload = <String, Object?>{
        'v': '2',
        'ps': '~~~',
        'add': 'u.example.com',
        'port': '8443',
        'id': 'aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee',
        'aid': '0',
        'scy': 'aes-128-gcm',
        'net': 'ws',
        'path': '/u',
        'host': 'u.example.com',
        'tls': 'tls',
        'sni': 'u.example.com',
      };
      final String standard =
          base64.encode(utf8.encode(jsonEncode(payload)));
      expect(standard.contains('+'), isTrue);
      final String urlsafe =
          standard.replaceAll('+', '-').replaceAll('/', '_');
      expect(urlsafe, isNot(standard));
      final Map<String, Object?>? node =
          parseShareLink('vmess://$urlsafe');
      expect(node, isNotNull);
      expect(node!['name'], '~~~');
      expect(node['port'], 8443);
      expect(node['network'], 'ws');
    });

    test('vmess + grpc maps grpc-service-name from path', () {
      final Map<String, Object?>? node = parseShareLink(vmessLink(
        <String, Object?>{
          'v': '2',
          'ps': 'vmess-grpc',
          'add': 'g.example.com',
          'port': 443,
          'id': 'bbbbbbbb-cccc-dddd-eeee-ffffffffffff',
          'aid': 0,
          'net': 'grpc',
          'path': 'vmess-grpc-svc',
          'tls': 'tls',
          'sni': 'g.example.com',
        },
      ));
      expect(node, isNotNull);
      expect(node!['network'], 'grpc');
      expect(node['grpc-opts'], <String, Object?>{
        'grpc-service-name': 'vmess-grpc-svc',
      });
    });

    test('vmess + h2 maps h2-opts', () {
      final Map<String, Object?>? node = parseShareLink(vmessLink(
        <String, Object?>{
          'v': '2',
          'ps': 'vmess-h2',
          'add': 'h2.example.com',
          'port': '443',
          'id': 'cccccccc-dddd-eeee-ffff-000000000000',
          'aid': '0',
          'net': 'h2',
          'path': '/vmess-h2',
          'host': 'h2.example.com',
          'tls': 'tls',
        },
      ));
      expect(node, isNotNull);
      expect(node!['h2-opts'], <String, Object?>{
        'host': <String>['h2.example.com'],
        'path': '/vmess-h2',
      });
    });

    test('vmess defaults aid/cipher/net and accepts numeric port', () {
      final Map<String, Object?>? node = parseShareLink(vmessLink(
        <String, Object?>{
          'v': '2',
          'ps': 'vmess-min',
          'add': 'm.example.com',
          'port': 8080,
          'id': 'dddddddd-eeee-ffff-0000-111111111111',
        },
      ));
      expect(node, isNotNull);
      expect(node!['port'], 8080);
      expect(node['alterId'], 0);
      expect(node['cipher'], 'auto');
      expect(node['network'], 'tcp');
      expect(node['tls'], false);
    });

    test('vmess alpn and insecure fields are honoured', () {
      final Map<String, Object?>? node = parseShareLink(vmessLink(
        <String, Object?>{
          'v': '2',
          'ps': 'vmess-alpn',
          'add': 'a.example.com',
          'port': '443',
          'id': 'eeeeeeee-ffff-0000-1111-222222222222',
          'net': 'ws',
          'path': '/a',
          'host': 'a.example.com',
          'tls': 'tls',
          'sni': 'a.example.com',
          'alpn': 'h2,http/1.1',
          'allowInsecure': '1',
        },
      ));
      expect(node, isNotNull);
      expect(node!['alpn'], <String>['h2', 'http/1.1']);
      expect(node['skip-cert-verify'], true);
    });
  });

  group('trojan', () {
    test('trojan maps sni, insecure, ws and alpn', () {
      const String link = 'trojan://p%40ssw0rd@tj.example.com:443'
          '?sni=tj.example.com&allowInsecure=1&type=ws&path=%2Ftj'
          '&host=cdn.example.com&alpn=h2%2Chttp%2F1.1&fp=chrome#TJ';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], 'TJ');
      expect(node['type'], 'trojan');
      expect(node['server'], 'tj.example.com');
      expect(node['port'], 443);
      expect(node['password'], 'p@ssw0rd');
      expect(node['udp'], true);
      expect(node['network'], 'ws');
      // Trojan spells it `sni`, never `servername`.
      expect(node['sni'], 'tj.example.com');
      expect(node.containsKey('servername'), isFalse);
      expect(node['skip-cert-verify'], true);
      expect(node['alpn'], <String>['h2', 'http/1.1']);
      expect(node['client-fingerprint'], 'chrome');
      final Map<String, Object?> ws =
          node['ws-opts']! as Map<String, Object?>;
      expect(ws['path'], '/tj');
      final Map<String, Object?> headers =
          ws['headers']! as Map<String, Object?>;
      expect(headers['Host'], 'cdn.example.com');
    });

    test('trojan + grpc maps grpc-service-name', () {
      final Map<String, Object?>? node = parseShareLink(
        'trojan://pw@t.example.com:443?type=grpc'
        '&serviceName=trojan-grpc&sni=t.example.com#TG',
      );
      expect(node, isNotNull);
      expect(node!['network'], 'grpc');
      expect(node['grpc-opts'], <String, Object?>{
        'grpc-service-name': 'trojan-grpc',
      });
    });

    test('trojan without network defaults to tcp', () {
      final Map<String, Object?>? node = parseShareLink(
        'trojan://secret@t.example.com:443?sni=t.example.com#TCP',
      );
      expect(node, isNotNull);
      expect(node!['network'], 'tcp');
      expect(node.containsKey('ws-opts'), isFalse);
      expect(node.containsKey('skip-cert-verify'), isFalse);
    });
  });

  group('ss', () {
    test('ss SIP002 (base64 userinfo) keeps the #name', () {
      const String link =
          'ss://YWVzLTI1Ni1nY206dGVzdDEyMzQ@example.com:8388'
          '#%E6%B5%8B%E8%AF%95';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], '测试');
      expect(node['type'], 'ss');
      expect(node['server'], 'example.com');
      expect(node['port'], 8388);
      expect(node['port'], isA<int>());
      expect(node['cipher'], 'aes-256-gcm');
      expect(node['password'], 'test1234');
      expect(node['udp'], true);
      expect(node.containsKey('plugin'), isFalse);
    });

    test('ss legacy base64 (whole userinfo@host:port) is supported', () {
      const String link =
          'ss://YWVzLTEyOC1nY206bXlwYXNzQDEuMi4zLjQ6ODM4OA==#legacy';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], 'legacy');
      expect(node['cipher'], 'aes-128-gcm');
      expect(node['password'], 'mypass');
      expect(node['server'], '1.2.3.4');
      expect(node['port'], 8388);
    });

    test('ss simple-obfs plugin is converted to mihomo obfs', () {
      final Map<String, Object?>? node = parseShareLink(
        'ss://YWVzLTI1Ni1nY206dGVzdDEyMzQ@ss.example.com:8388/'
        '?plugin=obfs-local%3Bobfs%3Dhttp%3Bobfs-host%3Dbing.com#Obfs',
      );
      expect(node, isNotNull);
      expect(node!['plugin'], 'obfs');
      expect(node['plugin-opts'], <String, Object?>{
        'mode': 'http',
        'host': 'bing.com',
      });
    });

    test('ss v2ray-plugin plugin is converted to mihomo v2ray-plugin', () {
      final Map<String, Object?>? node = parseShareLink(
        'ss://YWVzLTI1Ni1nY206dGVzdDEyMzQ@ss.example.com:8388/'
        '?plugin=v2ray-plugin%3Bmode%3Dwebsocket%3Bhost%3Dv2.example.com'
        '%3Bpath%3D%2Fws%3Btls#V2',
      );
      expect(node, isNotNull);
      expect(node!['plugin'], 'v2ray-plugin');
      expect(node['plugin-opts'], <String, Object?>{
        'mode': 'websocket',
        'host': 'v2.example.com',
        'path': '/ws',
        'tls': true,
      });
    });

    test('ss with an unsupported plugin is skipped', () {
      expect(
        parseShareLink(
          'ss://YWVzLTI1Ni1nY206dGVzdDEyMzQ@ss.example.com:8388/'
          '?plugin=shadow-tls%3Bhost%3Dx#BadPlugin',
        ),
        isNull,
      );
    });
  });

  group('hysteria2', () {
    test('hysteria2 maps obfs, insecure, alpn and sni', () {
      const String link = 'hysteria2://letmein@hy.example.com:443'
          '?sni=hy.example.com&insecure=1&obfs=salamander'
          '&obfs-password=salamanderpass&alpn=h3#HY2';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], 'HY2');
      expect(node['type'], 'hysteria2');
      expect(node['server'], 'hy.example.com');
      expect(node['port'], 443);
      expect(node['password'], 'letmein');
      expect(node['sni'], 'hy.example.com');
      expect(node['skip-cert-verify'], true);
      expect(node['obfs'], 'salamander');
      expect(node['obfs-password'], 'salamanderpass');
      expect(node['alpn'], <String>['h3']);
      expect(node['udp'], isNull);
    });

    test('hy2 alias produces a hysteria2 proxy', () {
      final Map<String, Object?>? node =
          parseShareLink('hy2://pw@hy.example.com:8443?insecure=1#H');
      expect(node, isNotNull);
      expect(node!['type'], 'hysteria2');
      expect(node['port'], 8443);
      expect(node['skip-cert-verify'], true);
      expect(node.containsKey('sni'), isFalse);
    });

    test('hysteria2 maps mport to ports and pinSHA256 to fingerprint', () {
      final Map<String, Object?>? node = parseShareLink(
        'hysteria2://pw@hy.example.com:443?mport=20000-30000'
        '&pinSHA256=sha256%3Aabc&sni=hy.example.com#MPORT',
      );
      expect(node, isNotNull);
      expect(node!['ports'], '20000-30000');
      expect(node['fingerprint'], 'sha256:abc');
    });
  });

  group('tuic', () {
    test('tuic maps congestion-controller and udp-relay-mode', () {
      const String link = 'tuic://0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0'
          ':secretpass@tu.example.com:443'
          '?congestion_control=bbr&alpn=h3&sni=tu.example.com'
          '&allow_insecure=1&udp_relay_mode=native#TUIC';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], 'TUIC');
      expect(node['type'], 'tuic');
      expect(node['server'], 'tu.example.com');
      expect(node['port'], 443);
      expect(node['uuid'], '0f1e2d3c-4b5a-6978-8796-a5b4c3d2e1f0');
      expect(node['password'], 'secretpass');
      expect(node['congestion-controller'], 'bbr');
      expect(node['udp-relay-mode'], 'native');
      expect(node['alpn'], <String>['h3']);
      expect(node['sni'], 'tu.example.com');
      expect(node['skip-cert-verify'], true);
    });

    test('tuic keeps colons inside the password', () {
      final Map<String, Object?>? node = parseShareLink(
        'tuic://uuid-value:pa%3Ass@tu.example.com:443#ColonPass',
      );
      expect(node, isNotNull);
      expect(node!['uuid'], 'uuid-value');
      expect(node['password'], 'pa:ss');
    });
  });

  group('socks / http', () {
    test('socks5 with credentials', () {
      final Map<String, Object?>? node =
          parseShareLink('socks5://user:p%40ss@127.0.0.1:1080#SOCKS');
      expect(node, isNotNull);
      expect(node!['name'], 'SOCKS');
      expect(node['type'], 'socks5');
      expect(node['server'], '127.0.0.1');
      expect(node['port'], 1080);
      expect(node['username'], 'user');
      expect(node['password'], 'p@ss');
      expect(node.containsKey('tls'), isFalse);
    });

    test('socks alias without credentials', () {
      final Map<String, Object?>? node =
          parseShareLink('socks://127.0.0.1:1080#NoAuth');
      expect(node, isNotNull);
      expect(node!['type'], 'socks5');
      expect(node.containsKey('username'), isFalse);
      expect(node.containsKey('password'), isFalse);
    });

    test('http proxy (plain and TLS)', () {
      final Map<String, Object?>? plain =
          parseShareLink('http://127.0.0.1:8080#HTTP');
      expect(plain, isNotNull);
      expect(plain!['type'], 'http');
      expect(plain['port'], 8080);
      expect(plain.containsKey('tls'), isFalse);

      final Map<String, Object?>? secure =
          parseShareLink('https://user:pass@proxy.example.com:8443#HTTPS');
      expect(secure, isNotNull);
      expect(secure!['type'], 'http');
      expect(secure['tls'], true);
      expect(secure['username'], 'user');
      expect(secure['password'], 'pass');
    });

    test('http/socks links without an explicit port are rejected', () {
      expect(parseShareLink('https://www.example.com/path'), isNull);
      expect(parseShareLink('http://example.com'), isNull);
      expect(parseShareLink('socks5://example.com'), isNull);
      expect(parseShareLink('socks://example.com/'), isNull);
    });
  });

  group('ssr', () {
    test('ssr base64 payload with base64 remarks', () {
      const String link =
          'ssr://MS4yLjMuNDo4Mzg4Om9yaWdpbjphZXMtMjU2LWNmYjpwbGFpbjpjM055'
          'Y0dGemN3Lz9yZW1hcmtzPVUxTlM2SXFDNTRLNQ';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], 'SSR节点');
      expect(node['type'], 'ssr');
      expect(node['server'], '1.2.3.4');
      expect(node['port'], 8388);
      expect(node['cipher'], 'aes-256-cfb');
      expect(node['password'], 'ssrpass');
      expect(node['protocol'], 'origin');
      expect(node['obfs'], 'plain');
    });

    test('broken ssr payload returns null instead of throwing', () {
      expect(parseShareLink('ssr://bm90LWFuLXNzci1wYXlsb2Fk'), isNull);
      expect(parseShareLink('ssr://'), isNull);
    });
  });

  group('invalid input', () {
    test('malformed strings return null', () {
      expect(parseShareLink(''), isNull);
      expect(parseShareLink('   '), isNull);
      expect(parseShareLink('hello world'), isNull);
      expect(parseShareLink('vless://'), isNull);
      expect(parseShareLink('vless://uuid@host-without-port'), isNull);
      expect(parseShareLink('vless://@host:443'), isNull);
      expect(parseShareLink('vmess://not-base64!!'), isNull);
      expect(parseShareLink('vmess://bm90IGpzb24='), isNull);
      expect(parseShareLink('ftp://example.com:21'), isNull);
      expect(parseShareLink('ss://'), isNull);
      expect(parseShareLink('trojan://'), isNull);
      expect(parseShareLink('hysteria2://'), isNull);
      expect(parseShareLink('tuic://'), isNull);
      expect(parseShareLink('://missing-scheme'), isNull);
    });

    test('malformed percent escapes do not throw', () {
      expect(
        () => parseShareLink('vless://u@h.example.com:443?path=%ZZ&sni=%'),
        returnsNormally,
      );
      expect(
        () => parseShareLink(
          'trojan://pw@h.example.com:443?sni=%E9%A6%99%ZZ',
        ),
        returnsNormally,
      );
      expect(
        () => parseShareLinks('%E9%A6%99%ZZ\nss://'),
        returnsNormally,
      );
    });

    test('ss with a port-less host or missing credentials is rejected', () {
      expect(parseShareLink('ss://YWVzLTI1Ni1nY206cGFzcw@host-without-port'),
          isNull);
      expect(parseShareLink('ss://@example.com:8388#NoCreds'), isNull);
    });
  });

  group('parseShareLinks', () {
    test('parses three lines, de-duplicates names and keeps order', () {
      const String text = '\n'
          'vless://11111111-1111-1111-1111-111111111111@a.example.com:443'
          '?security=tls&sni=a.example.com#HK\n'
          'vless://22222222-2222-2222-2222-222222222222@b.example.com:443'
          '?security=tls&sni=b.example.com#HK\n'
          'trojan://pass@c.example.com:443#JP\n';
      final List<Map<String, Object?>> nodes = parseShareLinks(text);
      expect(nodes.length, 3);
      expect(
        nodes.map((Map<String, Object?> node) => node['name']).toList(),
        <Object?>['HK', 'HK-2', 'JP'],
      );
      expect(nodes[0]['server'], 'a.example.com');
      expect(nodes[1]['server'], 'b.example.com');
      expect(nodes[2]['type'], 'trojan');
    });

    test('skips a name that is already taken (HK, HK-2, HK)', () {
      const String text = '\n'
          'vless://11111111-1111-1111-1111-111111111111@a.example.com:443'
          '?security=tls#HK\n'
          'vless://22222222-2222-2222-2222-222222222222@b.example.com:443'
          '?security=tls#HK-2\n'
          'vless://33333333-3333-3333-3333-333333333333@c.example.com:443'
          '?security=tls#HK\n';
      final List<Map<String, Object?>> nodes = parseShareLinks(text);
      expect(
        nodes.map((Map<String, Object?> node) => node['name']).toList(),
        <Object?>['HK', 'HK-2', 'HK-3'],
      );
    });

    test('decodes a whole base64 subscription', () {
      const String links = 'vless://11111111-1111-1111-1111-111111111111'
          '@a.example.com:443?security=tls&sni=a.example.com#A\n'
          'trojan://pw@b.example.com:443#B\n'
          'ss://YWVzLTI1Ni1nY206dGVzdDEyMzQ@c.example.com:8388#C\n';
      final String wrapped = base64.encode(utf8.encode(links));
      final List<Map<String, Object?>> nodes = parseShareLinks(wrapped);
      expect(nodes.length, 3);
      expect(
        nodes.map((Map<String, Object?> node) => node['name']).toList(),
        <Object?>['A', 'B', 'C'],
      );
      expect(nodes[1]['type'], 'trojan');
      expect(nodes[2]['type'], 'ss');
    });

    test('decodes a whole base64url (unpadded) subscription', () {
      const String links = 'trojan://pw@b.example.com:443#B\n'
          'ss://YWVzLTI1Ni1nY206dGVzdDEyMzQ@c.example.com:8388#C\n'
          'vless://11111111-1111-1111-1111-111111111111@a.example.com:443'
          '?security=tls#A\n';
      final String wrapped = base64Url
          .encode(utf8.encode(links))
          .replaceAll('=', '');
      final List<Map<String, Object?>> nodes = parseShareLinks(wrapped);
      expect(nodes.length, 3);
      expect(nodes.first['name'], 'B');
      expect(nodes.last['name'], 'A');
    });

    test('skips comments, blank lines, junk and unsupported schemes', () {
      const String text = '\n'
          '# ClashDeck subscription\n'
          '\n'
          'vless://11111111-1111-1111-1111-111111111111@a.example.com:443'
          '?security=tls#A\n'
          '   # indented comment\n'
          'garbage line\n'
          'ftp://example.com:21\n'
          '    \n';
      final List<Map<String, Object?>> nodes = parseShareLinks(text);
      expect(nodes.length, 1);
      expect(nodes.single['name'], 'A');
    });

    test('vmess 认 `t` / `p` 短键（部分面板这么写）', () {
      final String json = '{"v":"2","ps":"短键节点","t":"short.example.com",'
          '"p":"8443","id":"cd0777c4-1adb-4a8c-8f21-906ba3fea8f8",'
          '"aid":"0","scy":"auto","net":"ws","type":"none","path":"/ws","tls":"tls"}';
      final String link =
          'vmess://${base64Encode(utf8.encode(json))}';
      final Map<String, Object?>? node = parseShareLink(link);
      expect(node, isNotNull);
      expect(node!['name'], '短键节点');
      expect(node['server'], 'short.example.com');
      expect(node['port'], 8443);
      expect(node['tls'], isTrue);
    });

    test('never throws on garbage input', () {
      expect(parseShareLinks(''), isEmpty);
      expect(parseShareLinks('!!! ???'), isEmpty);
      expect(parseShareLinks('A' * 100), isEmpty);
      expect(parseShareLinks('x' * 33), isEmpty);
      expect(parseShareLinks('#only\n#comments\n'), isEmpty);
    });
  });
}
