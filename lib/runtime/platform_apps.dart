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
}

/// 通过同一个 MethodChannel 问 Android 要应用清单。
///
/// 桌面/测试环境没有这个通道：一律返回空表，让设置页显示"当前平台不支持"，
/// 而不是抛异常。
class PlatformApps {
  const PlatformApps._();

  static const MethodChannel _channel = MethodChannel('dev.clashdeck/runtime');

  static Future<List<AppEntry>> list() async {
    try {
      final raw = await _channel.invokeMethod<List<Object?>>('listApps');
      if (raw == null) return const [];
      final out = <AppEntry>[];
      for (final item in raw) {
        if (item is! Map) continue;
        final pkg = item['package'] as String?;
        if (pkg == null || pkg.isEmpty) continue;
        out.add(
          AppEntry(
            package: pkg,
            label: (item['label'] as String?) ?? pkg,
            system: item['system'] == true,
          ),
        );
      }
      return out;
    } on MissingPluginException {
      return const [];
    } on PlatformException {
      return const [];
    }
  }
}
