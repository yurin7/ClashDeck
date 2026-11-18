import 'package:clashdeck/core/edit/config_ops.dart';
import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

const fixture = r'''# ClashDeck 测试配置
mixed-port: 7890
allow-lan: false
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
secret: ""

proxies:
  # 香港节点
  - name: "HK-01"
    type: vless
    server: hk01.example.com
    port: 443
    uuid: 11111111-2222-3333-4444-555555555555
    network: tcp
    tls: true
    udp: true

  - name: JP-01 # 东京
    type: vless
    server: jp01.example.com
    port: 443
    uuid: 66666666-7777-8888-9999-000000000000
    network: ws
    tls: true
    ws-opts:
      path: /ws
      headers:
        Host: jp01.example.com

proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - "HK-01"
      - JP-01
  - name: AUTO
    type: url-test
    url: http://www.gstatic.com/generate_204
    interval: 300
    proxies:
      - JP-01

rules:
  - DOMAIN-SUFFIX,google.com,PROXY  # 谷歌
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
''';

YamlDoc load() {
  final doc = YamlDoc.parse(fixture);
  expect(doc.isValid, isTrue, reason: '${doc.error}');
  return doc;
}

void main() {
  group('解析', () {
    test('基本结构', () {
      final p = Profile.from(load());
      expect(p.mode, 'rule');
      expect(p.proxies.map((e) => e.name), ['HK-01', 'JP-01']);
      expect(p.proxies.first.type, 'vless');
      expect(p.proxies.first.port, 443);
      expect(p.groups.map((e) => e.name), ['PROXY', 'AUTO']);
      expect(p.groups.first.members, ['HK-01', 'JP-01']);
      expect(p.groups.first.computedMembers, isFalse);
      expect(p.rules.map((r) => r.type), ['DOMAIN-SUFFIX', 'GEOIP', 'MATCH']);
      expect(p.rules.first.target, 'PROXY');
      expect(p.rules[2].target, 'PROXY');
      expect(p.ungroupedNodes.map((e) => e.name), isEmpty);
    });

    test('include-all 组标记为运行时计算成员', () {
      final doc = YamlDoc.parse('''
proxy-groups:
  - name: ALL
    type: select
    include-all: true
''');
      final p = Profile.from(doc);
      expect(p.groups.single.computedMembers, isTrue);
    });

    test('空文本合法且有默认 mode', () {
      final p = Profile.from(YamlDoc.parse(''));
      expect(p.mode, 'rule');
      expect(p.proxies, isEmpty);
      expect(p.groups, isEmpty);
      expect(p.rules, isEmpty);
    });
  });

  group('节点增删改', () {
    test('新增节点：注释与既有文本逐字保留', () {
      final doc = load();
      final next = ConfigOps.addProxy(doc, {
        'name': 'SG-01',
        'type': 'vless',
        'server': 'sg01.example.com',
        'port': 443,
        'uuid': 'aaaa',
      });
      final p = Profile.from(next);
      expect(p.proxies.map((e) => e.name), ['HK-01', 'JP-01', 'SG-01']);
      // 原文件里 HK-01 上方的注释还在
      expect(next.text, contains('# 香港节点'));
      expect(next.text, contains('# 东京'));
      expect(next.text, contains('DOMAIN-SUFFIX,google.com,PROXY  # 谷歌'));
      // 头部注释保持第一行
      expect(next.text.startsWith('# ClashDeck 测试配置'), isTrue);
      // 新节点写成块状
      expect(next.text, contains('- name: SG-01'));
      expect(next.text, isNot(contains('{name: SG-01')));
    });

    test('新增节点：自动加入指定组', () {
      final next = ConfigOps.addProxy(
        load(),
        {
          'name': 'SG-01',
          'type': 'vless',
          'server': 'sg01',
          'port': 443,
          'uuid': 'a',
        },
        intoGroups: ['PROXY'],
      );
      final p = Profile.from(next);
      expect(p.group('PROXY')!.members, ['HK-01', 'JP-01', 'SG-01']);
    });

    test('重名节点抛异常', () {
      expect(
        () => ConfigOps.addProxy(load(), {'name': 'HK-01', 'type': 'vless'}),
        throwsA(isA<ConfigEditException>()),
      );
    });

    test('缺 name 抛异常', () {
      expect(
        () => ConfigOps.addProxy(load(), {'type': 'vless'}),
        throwsA(isA<ConfigEditException>()),
      );
    });

    test('删除节点：连带从组里移除', () {
      final next = ConfigOps.deleteProxy(load(), 'JP-01');
      final p = Profile.from(next);
      expect(p.proxies.map((e) => e.name), ['HK-01']);
      expect(p.group('PROXY')!.members, ['HK-01']);
      expect(p.group('AUTO')!.members, isEmpty);
    });

    test('组改名：同步规则目标与其它组成员', () {
      var doc = load();
      // 先让 AUTO 组把 PROXY 当成成员之一（组套组）
      doc = ConfigOps.addGroupMember(doc, 'AUTO', 'PROXY');
      final next = ConfigOps.renameGroup(doc, 'PROXY', 'PROXY2');
      final p = Profile.from(next);
      expect(p.groupNames, containsAll(['PROXY2', 'AUTO']));
      expect(p.group('AUTO')!.members, contains('PROXY2'));
      expect(p.rules[0].target, 'PROXY2');
      expect(p.rules[2].target, 'PROXY2');
      // yaml_edit 重写标量时会给含逗号的值加引号（语义等价、更安全），
      // 这里只断言内容与行尾注释都保住了。
      expect(next.text, contains('DOMAIN-SUFFIX,google.com,PROXY2'));
      expect(next.text, contains('  # 谷歌'));
    });

    test('改名节点：同步组成员引用', () {
      final next = ConfigOps.renameProxy(load(), 'JP-01', 'JP-东京');
      final p = Profile.from(next);
      expect(p.group('PROXY')!.members, ['HK-01', 'JP-东京']);
      expect(p.group('AUTO')!.members, ['JP-东京']);
      expect(next.text, contains('# 东京'));
    });

    test('改名到已存在的名字抛异常', () {
      expect(
        () => ConfigOps.renameProxy(load(), 'HK-01', 'JP-01'),
        throwsA(isA<ConfigEditException>()),
      );
    });

    test('patchProxy：改标量、加新键、删键', () {
      var next = ConfigOps.patchProxy(load(), 'HK-01', {
        'server': 'hk02.example.com',
      });
      expect(Profile.from(next).proxy('HK-01')!.server, 'hk02.example.com');
      expect(next.text, contains('# 香港节点'));

      next = ConfigOps.patchProxy(next, 'HK-01', {
        'sni': 'cdn.example.com',
        'reality-opts': {'public-key': 'PK', 'short-id': 'ab'},
      });
      final p = Profile.from(next);
      expect(p.proxy('HK-01')!.raw['sni'], 'cdn.example.com');
      expect(
        (p.proxy('HK-01')!.raw['reality-opts'] as Map)['public-key'],
        'PK',
      );
      expect(next.text, contains('reality-opts:'));
      expect(next.text, isNot(contains('reality-opts: {')));

      next = ConfigOps.patchProxy(next, 'HK-01', {'udp': null});
      expect(
        Profile.from(next).proxy('HK-01')!.raw.containsKey('udp'),
        isFalse,
      );
    });

    test('没有 proxies 键时新增会创建它', () {
      final doc = YamlDoc.parse('mixed-port: 7890\n');
      final next = ConfigOps.addProxy(doc, {
        'name': 'A',
        'type': 'vless',
        'server': 'a.example.com',
        'port': 1,
        'uuid': 'u',
      });
      final p = Profile.from(next);
      expect(p.proxies.single.name, 'A');
      expect(next.text, contains('mixed-port: 7890'));
      expect(next.text, contains('proxies:'));
    });
  });

  group('策略组', () {
    test('跨组移动节点', () {
      final next = ConfigOps.moveMember(
        load(),
        node: 'HK-01',
        fromGroup: 'PROXY',
        toGroup: 'AUTO',
      );
      final p = Profile.from(next);
      expect(p.group('PROXY')!.members, ['JP-01']);
      expect(p.group('AUTO')!.members, ['HK-01', 'JP-01']);
    });

    test('加入已存在的成员是幂等的', () {
      final next = ConfigOps.addGroupMember(load(), 'PROXY', 'HK-01');
      expect(Profile.from(next).group('PROXY')!.members, ['HK-01', 'JP-01']);
    });

    test('按位置插入成员', () {
      final next = ConfigOps.addGroupMember(load(), 'PROXY', 'X', at: 0);
      expect(Profile.from(next).group('PROXY')!.members, [
        'X',
        'HK-01',
        'JP-01',
      ]);
    });

    test('setGroupMembers 整体重写并按节点声明顺序归一化', () {
      final next = ConfigOps.setGroupMembers(load(), 'PROXY', [
        'JP-01',
        'HK-01',
      ]);
      expect(Profile.from(next).group('PROXY')!.members, ['HK-01', 'JP-01']);
    });

    test('加入节点后内置出站自动沉到底部', () {
      var next = ConfigOps.setGroupMembers(load(), 'PROXY', [
        'DIRECT',
        'HK-01',
      ]);
      // 旧配置把 DIRECT 写在前面，写回时先归一化。
      expect(Profile.from(next).group('PROXY')!.members, ['HK-01', 'DIRECT']);

      next = ConfigOps.addGroupMember(next, 'PROXY', 'JP-01');
      expect(Profile.from(next).group('PROXY')!.members, [
        'HK-01',
        'JP-01',
        'DIRECT',
      ]);
      // YAML 文本顺序与 UI 一致：DIRECT 必须在节点后面。
      expect(
        next.text.indexOf('DIRECT'),
        greaterThan(next.text.indexOf('HK-01')),
      );
    });

    test('连续加入多个节点仍按 proxies 顺序，内置沉底', () {
      var next = ConfigOps.setGroupMembers(load(), 'PROXY', <String>['DIRECT']);
      next = ConfigOps.addGroupMember(next, 'PROXY', 'JP-01');
      next = ConfigOps.addGroupMember(next, 'PROXY', 'HK-01');
      expect(Profile.from(next).group('PROXY')!.members, <String>[
        'HK-01',
        'JP-01',
        'DIRECT',
      ]);
    });

    test('组内顺序固定：节点 → 策略组 → DIRECT → REJECT', () {
      final next = ConfigOps.setGroupMembers(load(), 'PROXY', [
        'REJECT',
        'HK-01',
        'AUTO',
        'DIRECT',
        'JP-01',
      ]);
      expect(Profile.from(next).group('PROXY')!.members, [
        'HK-01',
        'JP-01',
        'AUTO',
        'DIRECT',
        'REJECT',
      ]);
    });

    test('删除成员后剩余顺序保持规范', () {
      var next = ConfigOps.setGroupMembers(load(), 'PROXY', [
        'HK-01',
        'JP-01',
        'DIRECT',
      ]);
      next = ConfigOps.removeGroupMember(next, 'PROXY', 'HK-01');
      expect(Profile.from(next).group('PROXY')!.members, ['JP-01', 'DIRECT']);
    });

    test('新建与删除策略组', () {
      var next = ConfigOps.addGroup(load(), {
        'name': 'FALLBACK',
        'type': 'fallback',
        'proxies': <Object?>['HK-01'],
      });
      expect(Profile.from(next).group('FALLBACK')!.members, ['HK-01']);

      next = ConfigOps.deleteGroup(next, 'FALLBACK');
      expect(Profile.from(next).group('FALLBACK'), isNull);
      expect(next.text, contains('# 谷歌'));
    });

    test('patchGroup 改字段', () {
      final next = ConfigOps.patchGroup(load(), 'AUTO', {'interval': 600});
      expect(Profile.from(next).group('AUTO')!.raw['interval'], 600);
    });
  });

  group('规则', () {
    test('追加规则到末尾', () {
      final next = ConfigOps.addRule(load(), 'DOMAIN,example.com,PROXY');
      final p = Profile.from(next);
      expect(p.rules.length, 4);
      expect(p.rules.last.raw, 'DOMAIN,example.com,PROXY');
      expect(next.text, contains('# 谷歌'));
    });

    test('按位置插入规则', () {
      final next = ConfigOps.addRule(
        load(),
        'PROCESS-NAME,Telegram.exe,PROXY',
        at: 0,
      );
      expect(Profile.from(next).rules.first.type, 'PROCESS-NAME');
    });

    test('删除规则', () {
      final p = Profile.from(ConfigOps.deleteRule(load(), 1));
      expect(p.rules.map((r) => r.type), ['DOMAIN-SUFFIX', 'MATCH']);
    });

    test('移动规则：把最后一条移到最前', () {
      final next = ConfigOps.moveRule(load(), 2, 0);
      final p = Profile.from(next);
      expect(p.rules.map((r) => r.type), ['MATCH', 'DOMAIN-SUFFIX', 'GEOIP']);
      expect(next.text, contains('# 谷歌'));
    });

    test('移动规则：把第一条移到最后', () {
      final next = ConfigOps.moveRule(load(), 0, 2);
      final p = Profile.from(next);
      expect(p.rules.map((r) => r.type), ['GEOIP', 'MATCH', 'DOMAIN-SUFFIX']);
    });

    test('非法规则位置抛异常', () {
      expect(
        () => ConfigOps.deleteRule(load(), 9),
        throwsA(isA<ConfigEditException>()),
      );
      expect(
        () => ConfigOps.moveRule(load(), 0, 9),
        throwsA(isA<ConfigEditException>()),
      );
    });
  });

  group('顶层配置', () {
    test('改标量', () {
      final next = ConfigOps.setTop(load(), 'mode', 'global');
      expect(Profile.from(next).mode, 'global');
      expect(next.text, contains('# ClashDeck 测试配置'));
    });

    test('新增顶层键（dns 块）', () {
      final next = ConfigOps.setTop(load(), 'dns', {
        'enable': true,
        'nameserver': <Object?>['223.5.5.5'],
      });
      final p = Profile.from(next);
      expect((p.root['dns'] as Map)['enable'], true);
    });

    test('删除顶层键', () {
      final next = ConfigOps.removeTop(load(), 'secret');
      expect(Profile.from(next).root.containsKey('secret'), isFalse);
    });
  });

  group('无损性', () {
    test('改一个标量时，其余文本长度只变化该标量', () {
      final doc = load();
      final next = ConfigOps.patchProxy(doc, 'HK-01', {
        'server': 'x.example.com',
      });
      final before = doc.text.split('\n');
      final after = next.text.split('\n');
      expect(after.length, before.length);
      var changed = 0;
      for (var i = 0; i < before.length; i++) {
        if (before[i] != after[i]) changed++;
      }
      expect(changed, 1);
    });

    test('链式编辑后仍是合法 YAML 且结构正确', () {
      var doc = load();
      doc = ConfigOps.addProxy(doc, {
        'name': 'N1',
        'type': 'trojan',
        'server': 'n1.example.com',
        'port': 8443,
        'password': 'p',
      });
      doc = ConfigOps.addGroup(doc, {'name': 'TROJAN', 'type': 'select'});
      doc = ConfigOps.addGroupMember(doc, 'TROJAN', 'N1');
      doc = ConfigOps.addRule(doc, 'MATCH,TROJAN');
      doc = ConfigOps.deleteProxy(doc, 'HK-01');
      final p = Profile.from(doc);
      expect(p.proxies.map((e) => e.name), ['JP-01', 'N1']);
      expect(p.group('TROJAN')!.members, ['N1']);
      expect(p.rules.last.target, 'TROJAN');
      expect(doc.isValid, isTrue);
    });
  });
  group('setAtOrCreate：缺失的中间映射自动补建', () {
    test('没有 tun 段时写 tun.stack 会整段建出来', () {
      final doc = load();
      expect(doc.plainAt(['tun']), isNull);
      final next = ConfigOps.setAtOrCreate(doc, ['tun', 'stack'], 'system');
      final tun = next.plainAt(['tun']) as Map;
      expect(tun['stack'], 'system');
      expect(next.isValid, isTrue);
    });

    test('已有 tun 段时只在里面加键', () {
      final doc = YamlDoc.parse('mixed-port: 7890\ntun:\n  enable: true\n');
      final next = ConfigOps.setAtOrCreate(doc, ['tun', 'mtu'], 1500);
      final tun = next.plainAt(['tun']) as Map;
      expect(tun['enable'], isTrue);
      expect(tun['mtu'], 1500);
    });

    test('父节点不是映射时报错而不是覆盖', () {
      final doc = YamlDoc.parse('mixed-port: 7890\ntun: false\n');
      expect(
        () => ConfigOps.setAtOrCreate(doc, ['tun', 'stack'], 'system'),
        throwsA(isA<ConfigEditException>()),
      );
    });
  });

  group('组成员', () {
    test('系统策略可以写进组的 proxies（DIRECT / REJECT 不是未知节点）', () {
      final doc = YamlDoc.parse(fixture);
      final withGroup = ConfigOps.addGroup(doc, {
        'name': 'EMPTY',
        'type': 'select',
      });
      final next = ConfigOps.addGroupMember(withGroup, 'EMPTY', 'DIRECT');
      final groups = next.plainAt(['proxy-groups']) as List;
      final empty =
          groups.firstWhere((g) => (g as Map)['name'] == 'EMPTY') as Map;
      expect(empty['proxies'], ['DIRECT']);
      // 再补一个 REJECT，顺序按加入顺序。
      final after = ConfigOps.addGroupMember(next, 'EMPTY', 'REJECT');
      final groupsAfter = after.plainAt(['proxy-groups']) as List;
      final emptyAfter =
          groupsAfter.firstWhere((g) => (g as Map)['name'] == 'EMPTY') as Map;
      expect(emptyAfter['proxies'], ['DIRECT', 'REJECT']);
    });
  });
}
