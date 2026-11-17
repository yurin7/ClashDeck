import 'dart:io';

import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/settings_state.dart';
import 'package:clashdeck/core/model/app_settings.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// 设置页每个开关都必须真的落到 YAML / meta 里。
///
/// 这一组用例是回归用的：早期 `SettingsState._set` 直接用 yaml_edit 的 update，
/// 配置里没有 `tun:` 段时写 `tun.stack` 会抛 Invalid path，界面看起来「点了没反应」，
/// 但 YAML 完全没变。现在统一走 `ConfigOps.setAtOrCreate`。
void main() {
  late Directory dir;
  late ProfileStore store;

  const base = '''
mixed-port: 7890
mode: rule
log-level: info
allow-lan: false
ipv6: false
proxies: []
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - DIRECT
rules:
  - MATCH,PROXY
''';

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clashdeck_settings');
    store = ProfileStore(dir);
    await store.create('t', base);
  });

  tearDown(() async {
    if (dir.existsSync()) await dir.delete(recursive: true);
  });

  Future<Map<String, Object?>> reloadYaml() async {
    final text = await store.read('t.yaml');
    expect(YamlDoc.parse(text).isValid, isTrue, reason: '写坏了 YAML：$text');
    return YamlDoc.parse(text).plainRoot;
  }

  test('没有 tun 段时改栈/MTU 会整段建出来', () async {
    final s = await SettingsState.load(store, 't.yaml');
    expect(s.tunStack, 'gvisor');
    await s.setTunStack('system');
    await s.setTunMtu(1500);

    final yaml = await reloadYaml();
    final tun = yaml['tun']! as Map;
    expect(tun['stack'], 'system');
    expect(tun['mtu'], 1500);
  });

  test('改分流 / 允许局域网 / IPv6 / 日志级别 都落到 YAML', () async {
    final s = await SettingsState.load(store, 't.yaml');
    await s.setMode('global');
    await s.setAllowLan(true);
    await s.setIpv6(true);
    await s.setLogLevel('debug');

    final yaml = await reloadYaml();
    expect(yaml['mode'], 'global');
    expect(yaml['allow-lan'], true);
    expect(yaml['ipv6'], true);
    expect(yaml['log-level'], 'debug');
  });

  test('DNS 段缺失时按开关建出来，已有值不被覆盖', () async {
    final s = await SettingsState.load(store, 't.yaml');
    await s.setDnsEnabled(true);
    await s.setDnsMode('redir-host');
    await s.setFakeIpRange('198.19.0.1/16');
    await s.setNameservers(['1.1.1.1', '8.8.8.8']);

    final dns = (await reloadYaml())['dns']! as Map;
    expect(dns['enable'], true);
    expect(dns['enhanced-mode'], 'redir-host');
    expect(dns['fake-ip-range'], '198.19.0.1/16');
    expect(dns['nameserver'], ['1.1.1.1', '8.8.8.8']);

    // 再读一次要能读回来同样的值。
    final again = await SettingsState.load(store, 't.yaml');
    expect(again.dnsMode, 'redir-host');
    expect(again.nameservers, ['1.1.1.1', '8.8.8.8']);
  });

  test('代理模式 / 分应用名单写进 sidecar meta，不污染 YAML', () async {
    final s = await SettingsState.load(store, 't.yaml');
    await s.setProxyMode(ProxyMode.portOnly);
    await s.setRouteMode(AppRouteMode.allowList);
    await s.setRoutePackages(['com.example.browser']);

    final yaml = await reloadYaml();
    expect(yaml.containsKey('proxyMode'), isFalse);
    final meta = await store.readMeta('t.yaml');
    final app = meta['app']! as Map;
    expect(app['proxyMode'], 'port');
    expect(app['routeMode'], 'allow');
    expect(app['routePackages'], ['com.example.browser']);

    final again = await SettingsState.load(store, 't.yaml');
    expect(again.app.proxyMode, ProxyMode.portOnly);
    expect(again.app.routePackages, ['com.example.browser']);
  });

  test('父节点写坏成标量时报错，而不是静默失败', () async {
    await store.write('t.yaml', 'tun: false\nmixed-port: 7890\n');
    final s = await SettingsState.load(store, 't.yaml');
    expect(s.tunStack, 'gvisor');

    await expectLater(s.setTunStack('system'), throwsA(isA<Exception>()));
    expect(await store.read('t.yaml'), contains('tun: false'));
  });

  test('自动保存开关写进 sidecar，默认开', () async {
    final s = await SettingsState.load(store, 't.yaml');
    expect(s.autoSave, isTrue, reason: '默认应为开');

    await s.setAutoSave(false);
    final meta = await store.readMeta('t.yaml');
    expect((meta['app']! as Map)['autoSave'], false);
    // 纯界面偏好，不该出现在 YAML 里。
    expect((await reloadYaml()).containsKey('autoSave'), isFalse);

    final again = await SettingsState.load(store, 't.yaml');
    expect(again.autoSave, isFalse);
  });

  test('老版本 meta 没有 autoSave 键时按开处理', () async {
    await store.writeMeta('t.yaml', {
      'app': {'proxyMode': 'tun', 'routeMode': 'all'},
    });
    final s = await SettingsState.load(store, 't.yaml');
    expect(s.autoSave, isTrue);
  });
}
