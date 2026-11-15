import 'package:clashdeck/core/schema/field_spec.dart';
import 'package:clashdeck/core/schema/group_schema.dart';
import 'package:clashdeck/core/schema/proxy_schema.dart';
import 'package:flutter_test/flutter_test.dart';

/// 编译期检查：这些列表必须是 const，否则本文件无法通过编译。
const List<ProxySchema> constProxySchemas = kProxySchemas;
const List<FieldSpec> constGroupSchema = kGroupSchema;
const List<String> constGroupTypes = kGroupTypes;

void main() {
  group('ProxySchema 结构完整性', () {
    test('schema 数量与类型正确', () {
      expect(constProxySchemas.length, 13);
      expect(kProxySchemas.length, constProxySchemas.length);
      for (final schema in kProxySchemas) {
        expect(schema.type, isNotEmpty);
        expect(schema.labelZh, isNotEmpty);
        expect(schema.fields, isNotEmpty);
        expect(kSupportedProxyTypes, contains(schema.type));
      }
    });

    test('每个 schema 的顶层 field key 不重复', () {
      for (final schema in kProxySchemas) {
        final keys = schema.fields.map((field) => field.key).toList();
        expect(
          keys.toSet().length,
          keys.length,
          reason: '${schema.type} 的顶层字段存在重复 key',
        );
      }
    });

    test('每个 schema 的 nested key 不重复', () {
      for (final schema in kProxySchemas) {
        final keys = schema.nested.map((map) => map.key).toList();
        expect(
          keys.toSet().length,
          keys.length,
          reason: '${schema.type} 的嵌套块存在重复 key',
        );
      }
    });

    test('每个嵌套块内部的 field key 不重复', () {
      for (final schema in kProxySchemas) {
        for (final map in schema.nested) {
          final keys = map.fields.map((field) => field.key).toList();
          expect(
            keys.toSet().length,
            keys.length,
            reason: '${schema.type} / ${map.key} 子字段存在重复 key',
          );
        }
      }
    });

    test('nested 块都能在 fields 中找到同名 map 入口', () {
      for (final schema in kProxySchemas) {
        for (final map in schema.nested) {
          final entry = schema.find(map.key);
          expect(entry, isNotNull, reason: '${schema.type} 缺少 ${map.key} 入口字段');
          expect(entry!.kind, FieldKind.map);
          expect(schema.nestedFor(map.key), same(map));
        }
      }
    });

    test('所有字段都有中文标签和一行说明', () {
      final allFields = <FieldSpec>[
        for (final schema in kProxySchemas) ...schema.fields,
        for (final schema in kProxySchemas)
          for (final map in schema.nested) ...map.fields,
        ...kGroupSchema,
      ];
      for (final field in allFields) {
        expect(field.key, isNotEmpty);
        expect(field.labelZh.trim(), isNotEmpty, reason: '${field.key} 缺少中文标签');
        expect(field.help, isNotNull, reason: '${field.key} 缺少 help');
        expect(
          field.help!.trim(),
          isNotEmpty,
          reason: '${field.key} 的 help 为空',
        );
      }
    });

    test('enumChoice 字段的 options 非空且包含默认值', () {
      final allFields = <FieldSpec>[
        for (final schema in kProxySchemas) ...schema.fields,
        for (final schema in kProxySchemas)
          for (final map in schema.nested) ...map.fields,
        ...kGroupSchema,
      ];
      for (final field in allFields) {
        if (field.kind != FieldKind.enumChoice) {
          continue;
        }
        expect(field.options, isNotNull, reason: '${field.key} 缺少 options');
        expect(field.options, isNotEmpty, reason: '${field.key} 的 options 为空');
        if (field.defaultValue != null) {
          expect(
            field.options,
            contains(field.defaultValue),
            reason: '${field.key} 的默认值不在 options 中',
          );
        }
      }
    });

    test('visibleWhen 引用的字段存在且条件合法', () {
      for (final schema in kProxySchemas) {
        for (final field in schema.fields) {
          final conditionKey = field.visibleWhenKey;
          if (conditionKey == null) {
            continue;
          }
          final condition = schema.find(conditionKey);
          expect(
            condition,
            isNotNull,
            reason: '${field.key} 引用了不存在的 $conditionKey',
          );
          switch (conditionKey) {
            case 'tls':
              expect(condition!.kind, FieldKind.bool);
              expect(field.visibleWhenValue, isTrue);
            case 'network':
              expect(condition!.kind, FieldKind.enumChoice);
              expect(condition.options, contains(field.visibleWhenValue));
            default:
              fail('未预期的条件字段 $conditionKey');
          }
        }
      }
      final vless = proxySchemaFor('vless')!;
      expect(vless.find('ws-opts')!.visibleWhenValue, 'ws');
      expect(vless.find('grpc-opts')!.visibleWhenValue, 'grpc');
      expect(vless.find('h2-opts')!.visibleWhenValue, 'h2');
      expect(vless.find('http-opts')!.visibleWhenValue, 'http');
      expect(vless.find('servername')!.visibleWhenKey, 'tls');
      expect(vless.find('xhttp-opts')!.visibleWhenValue, 'xhttp');
    });

    test('lookup 方法行为正确', () {
      final vless = proxySchemaFor('vless');
      expect(vless, isNotNull);
      expect(vless!.find('uuid'), isNotNull);
      expect(vless.fieldByKey('uuid')!.key, 'uuid');
      expect(vless.find('not-exist'), isNull);
      expect(vless.nestedFor('ws-opts'), isNotNull);
      expect(vless.nestedFor('ws-opts')!.find('path'), isNotNull);
      expect(vless.nestedFor('not-exist'), isNull);
    });
  });

  group('必填字段与凭证字段', () {
    test('六个主流协议都要求 name/type/server/port', () {
      const types = <String>[
        'vless',
        'vmess',
        'trojan',
        'ss',
        'hysteria2',
        'tuic',
      ];
      for (final type in types) {
        final schema = proxySchemaFor(type)!;
        final required = schema.fields
            .where((field) => field.required)
            .map((field) => field.key)
            .toSet();
        expect(
          required.containsAll(<String>['name', 'type', 'server', 'port']),
          isTrue,
          reason: '$type 缺少基础必填字段',
        );
      }
    });

    test('每个协议的 required 集合精确', () {
      const expected = <String, Set<String>>{
        'vless': {'name', 'type', 'server', 'port', 'uuid'},
        'vmess': {'name', 'type', 'server', 'port', 'uuid'},
        'trojan': {'name', 'type', 'server', 'port', 'password'},
        'ss': {'name', 'type', 'server', 'port', 'password'},
        'hysteria2': {'name', 'type', 'server', 'port', 'password'},
        'tuic': {'name', 'type', 'server', 'port'},
        'wireguard': {'name', 'type', 'private-key'},
        'socks5': {'name', 'type', 'server', 'port'},
        'http': {'name', 'type', 'server', 'port'},
        'snell': {'name', 'type', 'server', 'port', 'psk'},
        'ssh': {'name', 'type', 'server', 'port'},
        'anytls': {'name', 'type', 'server', 'port', 'password'},
        'ssr': {'name', 'type', 'server', 'port', 'password'},
      };
      for (final entry in expected.entries) {
        final schema = proxySchemaFor(entry.key)!;
        final required = schema.fields
            .where((field) => field.required)
            .map((field) => field.key)
            .toSet();
        expect(required, entry.value, reason: '${entry.key} 的必填集合不符');
      }
    });

    test('各协议凭证字段存在且密码类被标记 secret', () {
      const credentials = <String, List<String>>{
        'vless': ['uuid'],
        'vmess': ['uuid'],
        'trojan': ['password'],
        'ss': ['password'],
        'hysteria2': ['password'],
        'tuic': ['token', 'uuid', 'password'],
        'wireguard': ['private-key'],
        'snell': ['psk', 'userkey'],
        'ssh': ['password', 'private-key', 'private-key-passphrase'],
        'anytls': ['password'],
        'ssr': ['password'],
        'socks5': ['password'],
        'http': ['password'],
      };
      for (final entry in credentials.entries) {
        final schema = proxySchemaFor(entry.key)!;
        for (final key in entry.value) {
          expect(
            schema.find(key),
            isNotNull,
            reason: '${entry.key} 缺少凭证字段 $key',
          );
        }
      }
      expect(proxySchemaFor('trojan')!.find('password')!.secret, isTrue);
      expect(proxySchemaFor('ss')!.find('password')!.secret, isTrue);
      expect(proxySchemaFor('hysteria2')!.find('password')!.secret, isTrue);
      expect(proxySchemaFor('tuic')!.find('token')!.secret, isTrue);
      expect(proxySchemaFor('snell')!.find('psk')!.secret, isTrue);
      expect(proxySchemaFor('wireguard')!.find('private-key')!.secret, isTrue);
      expect(proxySchemaFor('anytls')!.find('password')!.secret, isTrue);
      expect(proxySchemaFor('vless')!.find('uuid')!.secret, isFalse);
    });

    test('每个协议都有 udp 字段', () {
      for (final schema in kProxySchemas) {
        expect(schema.find('udp'), isNotNull, reason: '${schema.type} 缺少 udp');
      }
    });
  });

  group('协议专属字段', () {
    test('VLESS 关键字段齐全', () {
      final vless = proxySchemaFor('vless')!;
      for (final key in <String>[
        'uuid',
        'flow',
        'encryption',
        'network',
        'tls',
        'reality-opts',
        'ws-opts',
        'grpc-opts',
        'xhttp-opts',
        'packet-encoding',
      ]) {
        expect(vless.find(key), isNotNull, reason: 'vless 缺少 $key');
      }
      expect(
        vless.find('flow')!.options,
        containsAll(<String>['', 'xtls-rprx-vision']),
      );
    });

    test('VMess 关键字段齐全', () {
      final vmess = proxySchemaFor('vmess')!;
      for (final key in <String>[
        'uuid',
        'alterId',
        'cipher',
        'network',
        'tls',
        'tlsmirror-opts',
        'mekya-opts',
        'mkcp-opts',
        'global-padding',
        'authenticated-length',
      ]) {
        expect(vmess.find(key), isNotNull, reason: 'vmess 缺少 $key');
      }
      expect(vmess.find('alterId')!.kind, FieldKind.int);
      expect(vmess.find('cipher')!.defaultValue, 'auto');
    });

    test('Shadowsocks 加密方式与插件选项完整', () {
      final ss = proxySchemaFor('ss')!;
      final cipher = ss.find('cipher')!;
      expect(cipher.kind, FieldKind.enumChoice);
      expect(cipher.options, contains('2022-blake3-chacha20-poly1305'));
      expect(cipher.options, hasLength(17));
      final plugin = ss.find('plugin')!;
      expect(
        plugin.options,
        containsAll(<String>[
          '',
          'obfs',
          'v2ray-plugin',
          'shadow-tls',
          'restls',
        ]),
      );
      expect(ss.find('plugin-opts'), isNotNull);
      expect(ss.find('udp-over-tcp'), isNotNull);
    });

    test('Hysteria2 带宽/混淆/端口跳跃字段齐全', () {
      final hy2 = proxySchemaFor('hysteria2')!;
      for (final key in <String>[
        'ports',
        'hop-interval',
        'up',
        'down',
        'obfs',
        'obfs-password',
        'cwnd',
        'bbr-profile',
        'realm-opts',
        'ech-opts',
      ]) {
        expect(hy2.find(key), isNotNull, reason: 'hysteria2 缺少 $key');
      }
      expect(hy2.find('ports')!.kind, FieldKind.portRange);
      expect(
        hy2.find('obfs')!.options,
        containsAll(<String>['', 'salamander']),
      );
    });

    test('TUIC 关键字段齐全', () {
      final tuic = proxySchemaFor('tuic')!;
      for (final key in <String>[
        'token',
        'uuid',
        'password',
        'udp-relay-mode',
        'congestion-controller',
        'reduce-rtt',
        'udp-over-stream',
        'recv-window',
      ]) {
        expect(tuic.find(key), isNotNull, reason: 'tuic 缺少 $key');
      }
      expect(
        tuic.find('udp-relay-mode')!.options,
        containsAll(<String>['native', 'quic']),
      );
    });

    test('WireGuard 通过 peers 表达服务端信息', () {
      final wg = proxySchemaFor('wireguard')!;
      expect(wg.find('peers'), isNotNull);
      expect(wg.find('peers')!.kind, FieldKind.map);
      final peers = wg.nestedFor('peers')!;
      expect(peers.find('server'), isNotNull);
      expect(peers.find('port'), isNotNull);
      expect(peers.find('public-key'), isNotNull);
      expect(peers.find('allowed-ips'), isNotNull);
      expect(peers.find('reserved'), isNotNull);
      expect(wg.find('private-key')!.secret, isTrue);
    });

    test('Trojan 支持 ss-opts、Snell 支持 obfs-opts', () {
      expect(proxySchemaFor('trojan')!.nestedFor('ss-opts'), isNotNull);
      expect(
        proxySchemaFor('trojan')!.nestedFor('ss-opts')!.find('enabled'),
        isNotNull,
      );
      expect(proxySchemaFor('snell')!.nestedFor('obfs-opts'), isNotNull);
      expect(
        proxySchemaFor('snell')!.nestedFor('obfs-opts')!.find('mode')!.options,
        containsAll(<String>['http', 'tls']),
      );
    });

    test('嵌套块子字段覆盖完整', () {
      final vless = proxySchemaFor('vless')!;
      final ws = vless.nestedFor('ws-opts')!;
      for (final key in <String>[
        'path',
        'headers',
        'max-early-data',
        'early-data-header-name',
        'v2ray-http-upgrade',
        'v2ray-http-upgrade-fast-open',
      ]) {
        expect(ws.find(key), isNotNull, reason: 'ws-opts 缺少 $key');
      }
      final grpc = vless.nestedFor('grpc-opts')!;
      for (final key in <String>[
        'grpc-service-name',
        'grpc-user-agent',
        'ping-interval',
        'max-connections',
        'min-streams',
        'max-streams',
      ]) {
        expect(grpc.find(key), isNotNull, reason: 'grpc-opts 缺少 $key');
      }
      final reality = vless.nestedFor('reality-opts')!;
      expect(reality.find('public-key')!.required, isTrue);
      expect(reality.find('short-id'), isNotNull);
      final ech = vless.nestedFor('ech-opts')!;
      expect(ech.find('enable')!.kind, FieldKind.bool);
      expect(ech.find('config'), isNotNull);
      final xhttp = vless.nestedFor('xhttp-opts')!;
      expect(
        xhttp.find('mode')!.options,
        containsAll(<String>['auto', 'packet-up', 'stream-up', 'stream-one']),
      );
    });
  });

  group('supportedProxyTypes / proxySchemaFor', () {
    test('supportedProxyTypes 与 schema 表一致且无重复', () {
      expect(supportedProxyTypes, kSupportedProxyTypes);
      expect(
        supportedProxyTypes,
        kProxySchemas.map((schema) => schema.type).toList(),
      );
      expect(supportedProxyTypes.toSet().length, supportedProxyTypes.length);
    });

    test('未知类型返回 null', () {
      expect(proxySchemaFor('not-a-protocol'), isNull);
      expect(proxySchemaFor(''), isNull);
      expect(proxySchemaFor('VLESS'), isNull);
    });

    test('按类型逐个查找成功', () {
      for (final type in kSupportedProxyTypes) {
        final schema = proxySchemaFor(type);
        expect(schema, isNotNull, reason: '找不到 $type');
        expect(schema!.type, type);
      }
    });
  });

  group('分组 schema', () {
    test('分组类型列表正确', () {
      expect(constGroupTypes, <String>[
        'select',
        'url-test',
        'fallback',
        'load-balance',
        'relay',
      ]);
      expect(kGroupTypes, constGroupTypes);
    });

    test('分组字段覆盖完整且不重复', () {
      const expectedKeys = <String>{
        'name',
        'type',
        'proxies',
        'use',
        'url',
        'interval',
        'timeout',
        'max-failed-times',
        'empty-fallback',
        'lazy',
        'disable-udp',
        'filter',
        'exclude-filter',
        'exclude-type',
        'expected-status',
        'include-all',
        'include-all-proxies',
        'include-all-providers',
        'hidden',
        'icon',
      };
      final keys = kGroupSchema.map((field) => field.key).toList();
      expect(keys.toSet().length, keys.length);
      expect(keys.toSet(), expectedKeys);
      expect(kGroupSchema.length, expectedKeys.length);
      expect(constGroupSchema.length, kGroupSchema.length);
    });

    test('分组必填与关键字段类型正确', () {
      final name = kGroupSchema.firstWhere((field) => field.key == 'name');
      expect(name.required, isTrue);
      final type = kGroupSchema.firstWhere((field) => field.key == 'type');
      expect(type.required, isTrue);
      expect(type.kind, FieldKind.enumChoice);
      expect(type.options, kGroupTypes);
      expect(type.defaultValue, 'select');
      final lazy = kGroupSchema.firstWhere((field) => field.key == 'lazy');
      expect(lazy.kind, FieldKind.bool);
      expect(lazy.defaultValue, isTrue);
      final proxies = kGroupSchema.firstWhere(
        (field) => field.key == 'proxies',
      );
      expect(proxies.kind, FieldKind.stringList);
      final interval = kGroupSchema.firstWhere(
        (field) => field.key == 'interval',
      );
      expect(interval.kind, FieldKind.durationSeconds);
      final expectedStatus = kGroupSchema.firstWhere(
        (field) => field.key == 'expected-status',
      );
      expect(expectedStatus.kind, FieldKind.stringList);
    });

    test('groupUsesComputedMembers 判定自动成员', () {
      expect(
        groupUsesComputedMembers(<String, Object?>{'include-all': true}),
        isTrue,
      );
      expect(
        groupUsesComputedMembers(<String, Object?>{
          'include-all-proxies': true,
        }),
        isTrue,
      );
      expect(
        groupUsesComputedMembers(<String, Object?>{'filter': '香港'}),
        isTrue,
      );
      expect(
        groupUsesComputedMembers(<String, Object?>{'exclude-filter': '过期'}),
        isTrue,
      );
      expect(
        groupUsesComputedMembers(<String, Object?>{
          'type': 'select',
          'proxies': <String>['a', 'b'],
        }),
        isFalse,
      );
      expect(groupUsesComputedMembers(<String, Object?>{}), isFalse);
      expect(
        groupUsesComputedMembers(<String, Object?>{
          'type': 'url-test',
          'url': 'http://x',
          'interval': 300,
        }),
        isFalse,
      );
    });
  });
}
