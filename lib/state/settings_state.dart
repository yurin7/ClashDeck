import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/edit/config_ops.dart';
import '../core/edit/import_links.dart' as links;
import '../core/model/app_settings.dart';
import '../core/yaml/yaml_doc.dart';
import '../data/profile_store.dart';

/// 一份配置的"运行时设置"：一部分落在 YAML（内核真正读的键），
/// 一部分落在 sidecar meta（本 App 的行为）。
///
/// 为什么设置页直接写盘而不是走 [EditorState]：设置是"参数面板"，不是"编辑动作"，
/// 不应该出现在撤销栈里；每次改动立即持久化，语义清晰。
class SettingsState extends ChangeNotifier {
  SettingsState._(this.store, this.fileName, this._doc, this.app);

  final ProfileStore store;
  final String fileName;

  YamlDoc _doc;
  AppSettings app;

  static Future<SettingsState> load(ProfileStore store, String fileName) async {
    final text = await store.read(fileName);
    final doc = YamlDoc.parse(text);
    final meta = await store.readMeta(fileName);
    final raw = meta['app'];
    final app = raw is Map
        ? AppSettings.fromJson(raw.cast<String, Object?>())
        : AppSettings.defaults;
    final state = SettingsState._(store, fileName, doc, app);
    state._subscriptionUrl = meta['subscriptionUrl'] as String?;
    return state;
  }

  /// 只读快照：运行配置生成用。
  YamlDoc get doc => _doc;

  bool get valid => _doc.isValid;

  // ------------------------------------------------------------------ 内核

  bool get tunEnabled => _bool(['tun', 'enable'], true);

  /// YAML 里的 TUN 栈（gvisor / system / mixed）。
  String get tunStack =>
      (_doc.plainAt(['tun', 'stack']) as String?)?.trim().isNotEmpty == true
      ? (_doc.plainAt(['tun', 'stack']) as String).trim()
      : 'gvisor';

  int get tunMtu {
    final raw = _doc.plainAt(['tun', 'mtu']);
    return raw is num ? raw.toInt() : 9000;
  }

  bool get allowLan => _bool(['allow-lan'], false);

  bool get ipv6 => _bool(['ipv6'], false);

  String get mode {
    final raw = _doc.plainAt(['mode']);
    return raw is String && raw.trim().isNotEmpty ? raw.trim() : 'rule';
  }

  String get logLevel {
    final raw = _doc.plainAt(['log-level']);
    return raw is String && raw.trim().isNotEmpty ? raw.trim() : 'info';
  }

  // -------------------------------------------------------------------- DNS

  bool get dnsEnabled => _bool(['dns', 'enable'], true);

  String get dnsMode {
    final raw = _doc.plainAt(['dns', 'enhanced-mode']);
    return raw is String && raw.trim().isNotEmpty ? raw.trim() : 'fake-ip';
  }

  String get fakeIpRange {
    final raw = _doc.plainAt(['dns', 'fake-ip-range']);
    return raw is String && raw.trim().isNotEmpty
        ? raw.trim()
        : '198.18.0.1/16';
  }

  List<String> get nameservers {
    final raw = _doc.plainAt(['dns', 'nameserver']);
    if (raw is List) {
      return raw
          .map((e) => '$e'.trim())
          .where((e) => e.isNotEmpty)
          .toList(growable: false);
    }
    return const <String>[];
  }

  // ------------------------------------------------------------- 应用级开关

  bool get hasSubscription => _subscriptionUrl != null;

  String? _subscriptionUrl;

  String? get subscriptionUrl => _subscriptionUrl;

  /// 返回上一级时是否自动保存（纯界面偏好，存在 sidecar 的 app 段里）。
  bool get autoSave => app.autoSave;

  /// 「全局」模式下选定的出口；null 表示跟随内核默认（DIRECT）。
  String? get globalNode => app.globalNode;

  Future<void> reload() async {
    final text = await store.read(fileName);
    _doc = YamlDoc.parse(text);
    final meta = await store.readMeta(fileName);
    _subscriptionUrl = meta['subscriptionUrl'] as String?;
    final raw = meta['app'];
    if (raw is Map) app = AppSettings.fromJson(raw.cast<String, Object?>());
    notifyListeners();
  }

  Future<void> ensureLoaded() async {
    final meta = await store.readMeta(fileName);
    _subscriptionUrl = meta['subscriptionUrl'] as String?;
    final raw = meta['app'];
    if (raw is Map) app = AppSettings.fromJson(raw.cast<String, Object?>());
    notifyListeners();
  }

  // ------------------------------------------------------------------ 写入

  Future<void> setTunEnabled(bool value) => _set(['tun', 'enable'], value);

  Future<void> setTunStack(String value) => _set(['tun', 'stack'], value);

  Future<void> setTunMtu(int value) => _set(['tun', 'mtu'], value);

  Future<void> setAllowLan(bool value) => _set(['allow-lan'], value);

  Future<void> setIpv6(bool value) => _set(['ipv6'], value);

  Future<void> setMode(String value) => _set(['mode'], value);

  Future<void> setLogLevel(String value) => _set(['log-level'], value);

  Future<void> setDnsEnabled(bool value) => _set(['dns', 'enable'], value);

  Future<void> setDnsMode(String value) =>
      _set(['dns', 'enhanced-mode'], value);

  Future<void> setFakeIpRange(String value) =>
      _set(['dns', 'fake-ip-range'], value);

  Future<void> setNameservers(List<String> value) =>
      _set(['dns', 'nameserver'], value);

  Future<void> setProxyMode(ProxyMode value) =>
      _updateApp(app.copyWith(proxyMode: value));

  Future<void> setRouteMode(AppRouteMode value) =>
      _updateApp(app.copyWith(routeMode: value));

  Future<void> setRoutePackages(List<String> value) =>
      _updateApp(app.copyWith(routePackages: value));

  Future<void> setAutoUpdateHours(int value) =>
      _updateApp(app.copyWith(autoUpdateHours: value));

  Future<void> setLaunchOnBoot(bool value) =>
      _updateApp(app.copyWith(launchOnBoot: value));

  Future<void> setAutoSave(bool value) =>
      _updateApp(app.copyWith(autoSave: value));

  Future<void> setGlobalNode(String? value) =>
      _updateApp(app.copyWith(globalNode: value));

  /// 把一批解析好的节点写进这份配置（订阅刷新用：同名跳过）。
  ///
  /// 返回实际新增的节点数（跳过的、重名的都不算）。
  Future<int> importProxies(
    List<Map<String, Object?>> proxies, {
    bool skipExisting = true,
    String? group,
  }) async {
    if (proxies.isEmpty) return 0;
    final outcome = links.importProxies(
      _doc,
      proxies,
      skipExisting: skipExisting,
      group: group,
    );
    if (outcome.added.isEmpty) return 0;
    _doc = outcome.doc;
    await store.write(fileName, _doc.text);
    notifyListeners();
    return outcome.added.length;
  }

  /// 把一段文本（链接列表 / YAML 片段）合并进这份配置。
  Future<int> importLinks(String text, {String? group}) async {
    final outcome = links.importLinks(_doc, text, group: group);
    if (outcome.added.isEmpty) return 0;
    _doc = outcome.doc;
    await store.write(fileName, _doc.text);
    notifyListeners();
    return outcome.added.length;
  }

  // ------------------------------------------------------------------ 内部

  bool _bool(List<Object?> path, bool fallback) {
    final raw = _doc.plainAt(path);
    return raw is bool ? raw : fallback;
  }

  Future<void> _set(List<Object?> path, Object? value) async {
    if (_deepEquals(_doc.plainAt(path), value)) return;
    _doc = ConfigOps.setAtOrCreate(_doc, path, value);
    await store.write(fileName, _doc.text);
    notifyListeners();
  }

  Future<void> _updateApp(AppSettings next, {bool writeFile = true}) async {
    app = next;
    if (writeFile) {
      final meta = await store.readMeta(fileName);
      meta['app'] = next.toJson();
      await store.writeMeta(fileName, meta);
    }
    notifyListeners();
  }

  static bool _deepEquals(Object? a, Object? b) {
    if (identical(a, b)) return true;
    if (a is Map && b is Map) {
      if (a.length != b.length) return false;
      for (final key in b.keys) {
        if (!_deepEquals(a[key], b[key])) return false;
      }
      return true;
    }
    if (a is List && b is List) {
      if (a.length != b.length) return false;
      for (var i = 0; i < a.length; i++) {
        if (!_deepEquals(a[i], b[i])) return false;
      }
      return true;
    }
    return a == b;
  }
}
