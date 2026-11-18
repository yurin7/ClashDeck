import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 一个已安装应用（分应用代理用）。
class AppEntry {
  const AppEntry({
    required this.package,
    required this.label,
    this.system = false,
  });

  final String package;
  final String label;
  final bool system;

  @override
  String toString() => 'AppEntry($package, $label)';
}

/// 把 MethodChannel 返回的原始清单解析成 [AppEntry]。
///
/// 单独拆成顶层函数：调用侧用 `compute` 丢进 isolate，避免 300+ 个应用
/// 在首帧同步解析把过渡动画卡掉；测试也可以直接断言纯函数。
List<AppEntry> parseInstalledApps(List<Object?> raw) {
  final out = <AppEntry>[];
  for (final item in raw) {
    if (item is! Map) continue;
    final pkg = item['package'];
    if (pkg is! String || pkg.isEmpty) continue;
    final label = item['label'];
    out.add(
      AppEntry(
        package: pkg,
        label: label is String && label.isNotEmpty ? label : pkg,
        system: item['system'] == true,
      ),
    );
  }
  return out;
}

/// 通过同一个 MethodChannel 问 Android 要应用清单与图标。
///
/// 桌面/测试环境没有这个通道：一律返回空表，让设置页显示"当前平台不支持"，
/// 而不是抛异常。
class PlatformApps {
  const PlatformApps._();

  static const MethodChannel _channel = MethodChannel('dev.clashdeck/runtime');

  /// 图标缓存上限：分应用选择页一次最多几百个应用，32×32 的 PNG 很小，
  /// 缓存整页图标避免来回滚动重复过通道。
  static const int iconCacheLimit = 600;

  static final Map<String, Uint8List> _iconCache = <String, Uint8List>{};

  static Future<List<AppEntry>> list() async {
    List<Object?>? raw;
    try {
      raw = await _channel.invokeMethod<List<Object?>>('listApps');
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
    if (raw == null || raw.isEmpty) return const [];
    return compute(parseInstalledApps, raw);
  }

  /// 按包名批量取图标字节（32×32 PNG 的放大版，展示时缩到 32）。
  ///
  /// 已缓存的直接返回；未缓存的才过通道。Android 侧在后台线程解码，
  /// 调用方按批调用即可让图标渐进出现，不挡列表首帧。
  static Future<Map<String, Uint8List>> icons(List<String> packages) async {
    if (packages.isEmpty) return const {};
    final out = <String, Uint8List>{};
    final missing = <String>[];
    for (final pkg in packages) {
      final cached = _iconCache[pkg];
      if (cached != null) {
        out[pkg] = cached;
      } else {
        missing.add(pkg);
      }
    }
    if (missing.isEmpty) return out;
    try {
      final raw = await _channel.invokeMethod<Map<Object?, Object?>>(
        'listAppIcons',
        missing,
      );
      if (raw == null) return out;
      raw.forEach((key, value) {
        if (key is! String || value is! Uint8List) return;
        if (value.isEmpty) return;
        _putIcon(key, value);
        out[key] = value;
      });
    } on MissingPluginException {
      return out;
    } on PlatformException {
      return out;
    }
    return out;
  }

  static void _putIcon(String package, Uint8List bytes) {
    _iconCache[package] = bytes;
    while (_iconCache.length > iconCacheLimit) {
      _iconCache.remove(_iconCache.keys.first);
    }
  }

  /// 测试用：清空图标缓存，避免用例之间互相污染。
  @visibleForTesting
  static void clearIconCache() => _iconCache.clear();

  /// 测试用：当前缓存条目数。
  @visibleForTesting
  static int get iconCacheLength => _iconCache.length;
}
