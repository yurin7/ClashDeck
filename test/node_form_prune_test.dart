import 'package:clashdeck/core/schema/schema_prune.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('pruneValuesToSchema', () {
    test('切协议时删掉只属于旧协议的键', () {
      final values = <String, Object?>{
        'name': 'n1',
        'type': 'vless',
        'server': 'example.com',
        'port': 443,
        'uuid': 'u',
        'encryption': 'none', // 只有 vless 有
        'reality-opts': {'public-key': 'k'}, // vless 和 vmess 都有
      };
      final removed = pruneValuesToSchema('vmess', values);
      expect(removed, contains('encryption'));
      expect(values.containsKey('encryption'), isFalse);
      // uuid 与 reality-opts 是 vmess 也支持的键，必须保留
      expect(values['uuid'], 'u');
      expect(values['reality-opts'], isNotNull);
      expect(values['name'], 'n1');
      expect(values['type'], 'vless', reason: 'pruneValuesToSchema 不改 type 本身');
    });

    test('公共键（name/server/port/network）不会被删', () {
      final values = <String, Object?>{
        'name': 'n1',
        'type': 'vless',
        'server': 'a.com',
        'port': 443,
        'network': 'ws',
        'ws-opts': {'path': '/ws'},
      };
      final removed = pruneValuesToSchema('trojan', values);
      expect(removed, isEmpty);
      expect(values['ws-opts'], isNotNull);
    });

    test('schema 之外的自由字段保留', () {
      final values = <String, Object?>{
        'name': 'n1',
        'type': 'vless',
        'server': 'a.com',
        'port': 443,
        'dialer-proxy': 'PROXY-2',
        'smux': {'enabled': true},
      };
      pruneValuesToSchema('trojan', values);
      expect(values['dialer-proxy'], 'PROXY-2');
      expect(values['smux'], isNotNull);
    });

    test('未知类型不做任何删改', () {
      final values = <String, Object?>{
        'name': 'n1',
        'type': 'nope',
        'uuid': 'u',
      };
      final removed = pruneValuesToSchema('nope', values);
      expect(removed, isEmpty);
      expect(values['uuid'], 'u');
    });

    test('vless → ss 会删掉 uuid/reality-opts/flow 等专有键', () {
      final values = <String, Object?>{
        'name': 'n1',
        'type': 'vless',
        'server': 'a.com',
        'port': 443,
        'uuid': 'u',
        'flow': 'xtls-rprx-vision',
        'reality-opts': {'public-key': 'k'},
        'client-fingerprint': 'chrome',
      };
      final removed = pruneValuesToSchema('ss', values);
      expect(removed, containsAll(<String>['uuid', 'reality-opts', 'flow']));
      // client-fingerprint 是 ss 也支持的键
      expect(values.keys.toSet(), <String>{
        'name',
        'type',
        'server',
        'port',
        'client-fingerprint',
      });
    });

    test('修改的是传入的 map 本身（调用方依赖这一点）', () {
      final values = <String, Object?>{
        'name': 'n1',
        'type': 'vless',
        'flow': 'x',
      };
      final removed = pruneValuesToSchema('ss', values);
      expect(removed, ['flow']);
      expect(values.containsKey('flow'), isFalse);
    });
  });
}
