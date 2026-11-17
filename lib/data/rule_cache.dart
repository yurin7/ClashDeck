import 'dart:convert';
import 'dart:io';

import 'package:path_provider/path_provider.dart';

/// 规则集正文的本地缓存。
///
/// 之所以要把规则集落到普通文件、再用 `rule-providers: {type: file}` 指过去，
/// 是因为内核自己的 Go HTTP 客户端在部分网络下会直接 `EOF`（实测同一台设备上
/// Dart 侧 44 个文件全部拉得到，内核却一个都拉不下来）。落盘之后内核只读本地
/// 文件，运行时不依赖出网，导入后的二次拉取也省掉了。
class RuleCache {
  RuleCache._(this.dir);

  /// `<应用支持目录>/rules`。
  final Directory dir;

  static Future<RuleCache> open() async {
    final base = await getApplicationSupportDirectory();
    // 必须放在内核的工作目录（-d <appSupport>/mihomo）里面：
    // mihomo 只允许 provider 的 path 位于 home directory 或 SAFE_PATHS 下，
    // 放到别处会直接 fatal（path is not subpath of home directory）。
    final dir = Directory(
      '${base.path}${Platform.pathSeparator}mihomo${Platform.pathSeparator}rules',
    );
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return RuleCache._(dir);
  }

  /// 让内核读的正文文件。
  String pathFor(String id) => '${dir.path}${Platform.pathSeparator}$id.yaml';

  /// 记录来源 URL 与拉取时间，缓存丢了才有机会补拉。
  File _metaFor(String id) =>
      File('${dir.path}${Platform.pathSeparator}$id.meta.json');

  bool exists(String id) => File(pathFor(id)).existsSync();

  /// 没有缓存正文的规则集 id。
  List<String> missing(Iterable<String> ids) => [
    for (final id in ids)
      if (!exists(id)) id,
  ];

  Future<DateTime?> modifiedAt(String id) async {
    final file = File(pathFor(id));
    if (!await file.exists()) return null;
    return (await file.stat()).modified;
  }

  Future<void> write(String id, String text, {String? sourceUrl}) async {
    final target = File(pathFor(id));
    final tmp = File('${target.path}.tmp');
    await tmp.writeAsString(text, flush: true);
    await tmp.rename(target.path);
    final meta = _metaFor(id);
    await meta.writeAsString(
      jsonEncode(<String, Object?>{
        'url': sourceUrl,
        'fetchedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<String?> read(String id) async {
    final file = File(pathFor(id));
    if (!await file.exists()) return null;
    return file.readAsString();
  }

  /// 这个规则集当初是从哪拉的，补拉时用。
  Future<String?> sourceUrl(String id) async {
    final meta = _metaFor(id);
    if (!await meta.exists()) return null;
    try {
      final decoded = jsonDecode(await meta.readAsString());
      if (decoded is Map && decoded['url'] is String) {
        final url = (decoded['url'] as String).trim();
        return url.isEmpty ? null : url;
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<DateTime?> fetchedAt(String id) async {
    final meta = _metaFor(id);
    if (!await meta.exists()) return null;
    try {
      final decoded = jsonDecode(await meta.readAsString());
      if (decoded is Map && decoded['fetchedAt'] is String) {
        return DateTime.tryParse(decoded['fetchedAt'] as String)?.toLocal();
      }
    } on FormatException {
      return null;
    }
    return null;
  }

  Future<void> remove(String id) async {
    for (final file in [File(pathFor(id)), _metaFor(id)]) {
      if (await file.exists()) await file.delete();
    }
  }
}

/// 把规则集正文转成内核能读的文件内容。
///
/// `classical` 就是一行一条规则，原样写；`domain` / `ipcidr` 走 YAML 的
/// `payload:` 列表，和 HTTP provider 拿到的内容格式保持一致。
String ruleCacheBody(List<String> entries, String behavior) {
  // 内核的文件型 rule-provider 一律要求顶层有 `payload`，
  // 即使是 classical 也要写成 payload 列表（列表元素是整条规则）。
  final buffer = StringBuffer('payload:\n');
  for (final entry in entries) {
    buffer.writeln(_payloadLine(entry));
  }
  return buffer.toString();
}

/// 把拉到的原文转成内核能吃的缓存文件内容。
///
/// 域名/IP 类规则集原文本身就是 `payload:` 结构，直接原样落盘；
/// classical 的原文是逐行规则（可能带 `#` 注释），转成 payload 列表。
String ruleCacheBodyFromRaw(String raw, String behavior) {
  if (behavior.toLowerCase() != 'classical') return raw;
  // 有些 classical 原文本身就是 YAML（`payload:` 列表），不能再拆行包一层。
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    if (trimmed == 'payload:') return raw;
    break;
  }
  final entries = <String>[];
  for (final line in raw.split('\n')) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || trimmed.startsWith('#')) continue;
    entries.add(trimmed);
  }
  return ruleCacheBody(entries, behavior);
}

/// 单条 payload，按需加单引号，避免 `#`、`: ` 之类把 YAML 写坏。
String _payloadLine(String entry) {
  final needsQuote =
      entry.contains('#') ||
      entry.contains(': ') ||
      entry.startsWith('-') ||
      entry.startsWith('*') ||
      entry.startsWith('&') ||
      entry.startsWith('!') ||
      entry.startsWith('%') ||
      entry.startsWith('@') ||
      entry.startsWith('`') ||
      entry.startsWith('"') ||
      entry.startsWith("'");
  if (!needsQuote) return '  - $entry';
  final escaped = entry.replaceAll("'", "''");
  return "  - '$escaped'";
}
