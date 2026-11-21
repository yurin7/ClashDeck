import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 应用级偏好（跨配置的东西：当前选中的配置、最近一次订阅刷新时间…）。
///
/// 不放进任何 YAML：这些是"这个 App 的界面状态"，内核与别家客户端不需要也不该看到。
class AppPrefs {
  AppPrefs._(this._file, this._data);

  final File _file;
  final Map<String, Object?> _data;

  static const _fileName = 'app_prefs.json';

  static Future<AppPrefs> load({Directory? directory}) async {
    final base = directory ?? await getApplicationSupportDirectory();
    final file = File('${base.path}${Platform.pathSeparator}$_fileName');
    Map<String, Object?> data = const {};
    try {
      if (await file.exists()) {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) data = decoded.cast<String, Object?>();
      }
    } catch (_) {
      // 损坏的偏好文件当空处理，绝不能影响启动。
      data = const {};
    }
    return AppPrefs._(file, Map<String, Object?>.from(data));
  }

  String? get activeProfile => _data['activeProfile'] as String?;

  DateTime? get lastSubscriptionUpdate {
    final raw = _data['lastSubscriptionUpdate'] as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setActiveProfile(String? fileName) =>
      _put('activeProfile', fileName);

  Future<void> setLastSubscriptionUpdate(DateTime? time) =>
      _put('lastSubscriptionUpdate', time?.toIso8601String());

  /// 在线规则集是否自动更新。默认开。
  bool get ruleAutoUpdate => _data['ruleAutoUpdate'] as bool? ?? true;

  /// 自动更新间隔（小时）。只认 12 / 24 / 168，其它值按 24。
  int get ruleUpdateIntervalHours {
    final raw = _data['ruleUpdateIntervalHours'];
    final hours = raw is int ? raw : 24;
    return const {12, 24, 168}.contains(hours) ? hours : 24;
  }

  Future<void> setRuleAutoUpdate(bool enabled) =>
      _put('ruleAutoUpdate', enabled);

  Future<void> setRuleUpdateIntervalHours(int hours) =>
      _put('ruleUpdateIntervalHours', hours);

  // ------------------------------------------------------------ 检查更新（全局）

  /// 是否在启动后自动检查更新。默认关（用户要求「不自动联网」）。
  bool get updateAutoCheck => _data['updateAutoCheck'] as bool? ?? false;

  Future<void> setUpdateAutoCheck(bool enabled) =>
      _put('updateAutoCheck', enabled);

  /// 上次自动检查的时间（24h 节流用）。
  DateTime? get lastUpdateCheckAt {
    final raw = _data['lastUpdateCheckAt'] as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  Future<void> setLastUpdateCheckAt(DateTime? time) =>
      _put('lastUpdateCheckAt', time?.toIso8601String());

  /// 已经弹过提示的版本（同一版本只弹一次）。
  String? get lastNotifiedVersion => _data['lastNotifiedVersion'] as String?;

  Future<void> setLastNotifiedVersion(String? version) =>
      _put('lastNotifiedVersion', version);

  // ------------------------------------------------------------ 节点测速缓存

  static String _latencyKey(String profile, String node) =>
      'latency_${profile}_$node';
  static String _lastLatencyKey(String profile) => 'lastLatencyAt_$profile';

  /// 某配置缓存下来的节点延迟（毫秒；`-1` 表示超时/失败）。
  ///
  /// 只用于界面展示，不写入 YAML。
  Map<String, int?> latenciesOf(String profile) {
    final prefix = 'latency_${profile}_';
    final result = <String, int?>{};
    for (final entry in _data.entries) {
      if (!entry.key.startsWith(prefix)) continue;
      final value = entry.value;
      if (value is int) {
        result[entry.key.substring(prefix.length)] = value < 0 ? null : value;
      }
    }
    return result;
  }

  /// 上次测速时间（用于测速卡「上次测速 · 时间」与 NodeRow 状态）。
  DateTime? lastLatencyAt(String profile) {
    final raw = _data[_lastLatencyKey(profile)] as String?;
    return raw == null ? null : DateTime.tryParse(raw);
  }

  /// 覆盖写入一批延迟结果；`null` 记为 -1（超时）。
  Future<void> setLatencies(
    String profile,
    Map<String, int?> values, {
    DateTime? at,
  }) async {
    for (final entry in values.entries) {
      _data[_latencyKey(profile, entry.key)] = entry.value ?? -1;
    }
    _data[_lastLatencyKey(profile)] = (at ?? DateTime.now()).toIso8601String();
    try {
      await _file.writeAsString(jsonEncode(_data), flush: true);
    } catch (_) {
      // 写失败只影响下次展示，不影响当前会话。
    }
  }

  // ------------------------------------------------------------ 下载测速线路

  /// 测速线路名（`fast` / `google` / `github` / `custom`），默认 fast。
  String get speedTestSourceName =>
      _data['speedTestSource'] as String? ?? 'fast';

  /// 自定义测速地址（仅线路为 custom 时有意义）。
  String get speedTestCustomUrl => _data['speedTestCustomUrl'] as String? ?? '';

  Future<void> setSpeedTestSourceName(String value) =>
      _put('speedTestSource', value);

  Future<void> setSpeedTestCustomUrl(String value) =>
      _put('speedTestCustomUrl', value);

  Future<void> _put(String key, Object? value) async {
    if (value == null) {
      _data.remove(key);
    } else {
      _data[key] = value;
    }
    try {
      await _file.writeAsString(jsonEncode(_data), flush: true);
    } catch (_) {
      // 写失败只影响下次的默认选中，不影响当前会话。
    }
  }
}
