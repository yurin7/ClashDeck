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

  static Future<AppPrefs> load() async {
    final base = await getApplicationSupportDirectory();
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
