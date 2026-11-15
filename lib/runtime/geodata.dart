import 'dart:io';

import 'package:flutter/services.dart';

/// mihomo 的 GEOIP / GEOSITE 数据。
///
/// 为什么要在客户端里带数据而不是让内核自己下：mihomo 在 `-d` 目录里找不到
/// `geoip.metadb` / `geosite.dat` 时会**同步**去 GitHub Releases 下载（
/// `component/geodata/init.go`），下载失败就直接让带 `GEOIP` 规则的配置启动失败，
/// 而国内访问 GitHub Releases 常年几十 KB/s、几十秒就超时。首启体验不能赌这个。
///
/// 所以这里把数据打进 assets，第一次启动前复制到内核工作目录：
/// - `geoip.metadb` — GEOIP 规则用（mihomo v1.18+ 的默认数据格式）
/// - `geosite.dat` — GEOSITE 规则用
///
/// 复制失败不阻塞启动：内核会退回自己下载，只是慢/可能失败。
class Geodata {
  const Geodata._();

  /// 文件名 -> assets 路径。内核只认 `-d` 目录根下的这些文件名。
  static const Map<String, String> files = {
    'geoip.metadb': 'assets/geo/geoip.metadb',
    'geosite.dat': 'assets/geo/geosite.dat',
  };

  /// 确保 [workDir] 里有全部数据文件；返回实际写入的文件名。
  ///
  /// 已经存在且非空的文件不会重写（省掉每次启动几十 MB 的 IO）。
  static Future<List<String>> ensure(
    Directory workDir, {
    Future<ByteData> Function(String key)? load,
  }) async {
    final written = <String>[];
    await workDir.create(recursive: true);
    for (final entry in files.entries) {
      final target = File(
        '${workDir.path}${Platform.pathSeparator}${entry.key}',
      );
      if (await target.exists() && await target.length() > 0) continue;
      try {
        final data = await (load ?? rootBundle.load)(entry.value);
        final bytes = data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
        final tmp = File('${target.path}.tmp');
        await tmp.writeAsBytes(bytes, flush: true);
        await tmp.rename(target.path);
        written.add(entry.key);
      } catch (_) {
        // 缺数据也能启动，交给内核自己下载。
      }
    }
    return written;
  }

  /// 从原始字节装（测试用；避免依赖 asset bundle）。
  static Future<List<String>> ensureFrom(
    Directory workDir,
    Map<String, Uint8List> sources,
  ) {
    return ensure(
      workDir,
      load: (key) async {
        final name = key.split('/').last;
        final bytes = sources[name];
        if (bytes == null) throw StateError('missing $name');
        return ByteData.sublistView(bytes);
      },
    );
  }
}
