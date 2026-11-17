import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 磁盘上的一份配置（一个 `.yaml` 文件 = 一份配置）。
class StoredProfile {
  const StoredProfile({
    required this.fileName,
    required this.size,
    required this.modified,
  });

  final String fileName;
  final int size;
  final DateTime modified;

  /// 展示名：文件名去掉 `.yaml`。
  String get name => fileName.endsWith('.yaml')
      ? fileName.substring(0, fileName.length - 5)
      : fileName;

  String get subtitle {
    final kb = (size / 1024).toStringAsFixed(1);
    return '$kb KB · ${modified.month}/${modified.day} '
        '${modified.hour.toString().padLeft(2, '0')}:'
        '${modified.minute.toString().padLeft(2, '0')}';
  }
}

/// 配置文件仓库。**只负责字节进出**，不解析 YAML。
///
/// 设计：一份配置就是一个 `<名字>.yaml`，名字即文件名（应用层元数据留在文件名里，
/// 不往 YAML 里塞私有键，保证文件可以被 mihomo 或别家客户端直接读取）。
class ProfileStore {
  ProfileStore(this.dir);

  final Directory dir;

  /// 真机上打开 `<应用支持目录>/profiles`。
  static Future<ProfileStore> open() async {
    final base = await getApplicationSupportDirectory();
    final d = Directory('${base.path}${Platform.pathSeparator}profiles');
    if (!await d.exists()) await d.create(recursive: true);
    return ProfileStore(d);
  }

  Future<List<StoredProfile>> list() async {
    if (!await dir.exists()) return const [];
    final out = <StoredProfile>[];
    await for (final e in dir.list()) {
      if (e is! File || !e.path.toLowerCase().endsWith('.yaml')) continue;
      final stat = await e.stat();
      out.add(
        StoredProfile(
          fileName: e.uri.pathSegments.last,
          size: stat.size,
          modified: stat.modified,
        ),
      );
    }
    out.sort((a, b) => b.modified.compareTo(a.modified));
    return out;
  }

  Future<String> read(String fileName) async =>
      File('${dir.path}${Platform.pathSeparator}$fileName').readAsString();

  /// 新建一份配置，名字冲突时自动加 `-2`、`-3`…
  Future<StoredProfile> create(String name, String text) async {
    final fileName = await _freeFileName(name);
    await write(fileName, text);
    final stat = await File(_path(fileName)).stat();
    return StoredProfile(
      fileName: fileName,
      size: stat.size,
      modified: stat.modified,
    );
  }

  Future<void> write(String fileName, String text) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    // 先写临时文件再改名，避免写到一半被杀进程留下半截配置。
    final tmp = File('${_path(fileName)}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(_path(fileName));
  }

  Future<void> delete(String fileName) async {
    final f = File(_path(fileName));
    if (await f.exists()) await f.delete();
    final meta = File(_metaPath(fileName));
    if (await meta.exists()) await meta.delete();
  }

  Future<String> rename(String fileName, String newName) async {
    final target = await _freeFileName(newName);
    if (target != fileName) {
      await File(_path(fileName)).rename(_path(target));
      final meta = File(_metaPath(fileName));
      if (await meta.exists()) {
        await meta.rename(_metaPath(target));
      }
    }
    return target;
  }

  bool exists(String fileName) => File(_path(fileName)).existsSync();

  // ------------------------------------------------------------ sidecar meta
  //
  // 订阅地址这类"编辑器自己的记账"不能写进 YAML（内核不认、别家客户端会报未知键），
  // 所以放在同名 `.meta.json` 旁边。meta 缺失、损坏都当空处理，绝不影响配置文件本身。

  Future<Map<String, Object?>> readMeta(String fileName) async {
    final f = File(_metaPath(fileName));
    if (!await f.exists()) return <String, Object?>{};
    try {
      final decoded = jsonDecode(await f.readAsString());
      return decoded is Map
          ? decoded.cast<String, Object?>()
          : <String, Object?>{};
    } catch (_) {
      return <String, Object?>{};
    }
  }

  Future<void> writeMeta(String fileName, Map<String, Object?> meta) async {
    if (!await dir.exists()) await dir.create(recursive: true);
    final target = _metaPath(fileName);
    if (meta.isEmpty) {
      final f = File(target);
      if (await f.exists()) await f.delete();
      return;
    }
    final tmp = File('$target.tmp');
    await tmp.writeAsString(jsonEncode(meta), flush: true);
    await tmp.rename(target);
  }

  /// 记下订阅地址（保留 meta 里其它键）。
  Future<void> setSubscriptionUrl(String fileName, String? url) async {
    final meta = await readMeta(fileName);
    if (url == null || url.isEmpty) {
      meta.remove('subscriptionUrl');
    } else {
      meta['subscriptionUrl'] = url;
    }
    await writeMeta(fileName, meta);
  }

  Future<String?> subscriptionUrl(String fileName) async =>
      (await readMeta(fileName))['subscriptionUrl'] as String?;

  String _metaPath(String fileName) => '${_path(fileName)}.meta.json';

  String _path(String fileName) =>
      '${dir.path}${Platform.pathSeparator}$fileName';

  Future<String> _freeFileName(String name) async {
    final base = sanitizeName(name);
    var candidate = '$base.yaml';
    var i = 2;
    while (exists(candidate)) {
      candidate = '$base-$i.yaml';
      i++;
    }
    return candidate;
  }

  static const _illegal = r'<>:"/\|?*';

  /// 把任意字符串变成安全的文件名（保留中文）。
  static String sanitizeName(String raw) {
    final buf = StringBuffer();
    for (final rune in raw.trim().runes) {
      final ch = String.fromCharCode(rune);
      if (rune < 0x20 || _illegal.contains(ch)) {
        buf.write('_');
      } else {
        buf.write(ch);
      }
    }
    var s = buf.toString().trim();
    while (s.startsWith('.')) {
      s = s.substring(1);
    }
    if (s.isEmpty) s = 'config';
    if (s.length > 60) s = s.substring(0, 60);
    return s;
  }

  /// 一份"从零开始"的配置骨架（带注释，方便用户看懂）。
  static String starterConfig({String name = '我的配置'}) =>
      '''
# $name
# 由 ClashDeck 创建，mihomo / Clash 系列客户端可直接使用
mixed-port: 7890
allow-lan: false
bind-address: '*'
mode: rule
log-level: info
external-controller: 127.0.0.1:9090
ipv6: false

dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  nameserver:
    - 223.5.5.5
    - 119.29.29.29
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29

proxies: []

proxy-groups:
  - name: DEFAULT
    type: select
    proxies:
      - DIRECT
      - REJECT

rules:
  - GEOIP,CN,DIRECT
  - MATCH,DEFAULT
''';

  /// 用 [jsonEncode] 做备份/导出（方便分享给别的设备）。
  static String exportJson(String fileName, String text) =>
      const JsonEncoder.withIndent('  ')
          .convert({'fileName': fileName, 'text': text});
}
