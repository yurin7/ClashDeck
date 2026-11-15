import 'dart:convert';
import 'dart:io';

import '../model/profile.dart';
import '../yaml/yaml_doc.dart';
import 'share_link.dart';

/// 订阅响应头 `subscription-userinfo` 里的用量信息。
///
/// 各家机场都按 `upload=123;download=456;total=789;expire=1700000000` 这种格式发，
/// 单位是字节、`expire` 是秒级时间戳。
class SubscriptionUsage {
  const SubscriptionUsage({
    this.upload,
    this.download,
    this.total,
    this.expire,
  });

  final int? upload;
  final int? download;
  final int? total;
  final int? expire;

  int? get used {
    if (upload == null && download == null) return null;
    return (upload ?? 0) + (download ?? 0);
  }

  /// 「已用 1.2 GB / 共 100 GB」，缺字段就少说一句。
  String get label {
    final parts = <String>[];
    final u = used;
    final t = total;
    if (u != null && t != null && t > 0) {
      parts.add('已用 ${formatBytes(u)} / 共 ${formatBytes(t)}');
    } else if (t != null && t > 0) {
      parts.add('总流量 ${formatBytes(t)}');
    }
    final e = expire;
    if (e != null && e > 0) {
      final when = DateTime.fromMillisecondsSinceEpoch(e * 1000);
      parts.add('到期 ${when.year}-${_two(when.month)}-${_two(when.day)}');
    }
    return parts.join(' · ');
  }

  static String _two(int v) => v < 10 ? '0$v' : '$v';

  /// 解析失败（字段缺失/非数字）时返回 null，不抛异常。
  static SubscriptionUsage? parse(String? header) {
    if (header == null || header.trim().isEmpty) return null;
    final map = <String, int>{};
    for (final part in header.split(';')) {
      final idx = part.indexOf('=');
      if (idx <= 0) continue;
      final key = part.substring(0, idx).trim().toLowerCase();
      final value = int.tryParse(part.substring(idx + 1).trim());
      if (value != null && value >= 0) map[key] = value;
    }
    if (map.isEmpty) return null;
    return SubscriptionUsage(
      upload: map['upload'],
      download: map['download'],
      total: map['total'],
      expire: map['expire'],
    );
  }
}

String formatBytes(int bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  final text = value >= 100 || unit == 0
      ? value.toStringAsFixed(0)
      : value.toStringAsFixed(1);
  return '$text ${units[unit]}';
}

/// 一次订阅拉取/解析的产物。
class SubscriptionResult {
  const SubscriptionResult({
    required this.proxies,
    this.yamlConfig,
    this.title,
    this.usage,
  });

  /// 解析出来的节点（订阅是 Clash YAML 时，从它的 `proxies` 里取出来）。
  final List<Map<String, Object?>> proxies;

  /// 响应本身就是一份 Clash 配置时保留原文，界面上可以问用户"要不要存成新配置"。
  final String? yamlConfig;

  /// 订阅自称的名字（`profile-title` 头或响应文件名）。
  final String? title;

  final SubscriptionUsage? usage;

  bool get isEmpty => proxies.isEmpty;
  int get count => proxies.length;
}

final _yamlMarker = RegExp(
  r'^\s*(proxies|proxy-groups|mixed-port|port|socks-port)\s*:',
  multiLine: true,
  caseSensitive: false,
);
final _base64Chars = RegExp(r'^[A-Za-z0-9+/=_\-\s]+$');
final _hasScheme = RegExp(
  r'^[ \t]*(?:vless|vmess|trojan|ss|ssr|hysteria2?|hy2|tuic|socks5?|http|https)://',
  multiLine: true,
  caseSensitive: false,
);

/// 纯函数：把订阅响应体解析成节点。
///
/// 依次尝试：Clash YAML → base64（机场最常见的打包方式）→ 明文链接列表。
/// 什么都不成时抛 [ConfigEditException]，并把"看到的开头几个字节"带上，方便排查。
SubscriptionResult parseSubscriptionBody(String body, {String? title}) {
  final text = body.trim();
  if (text.isEmpty) throw ConfigEditException('订阅内容是空的');

  if (_yamlMarker.hasMatch(text)) {
    final doc = YamlDoc.parse(text);
    if (!doc.isValid) {
      throw ConfigEditException('订阅是一份 YAML，但解析失败：${doc.error?.message}');
    }
    final profile = Profile.from(doc);
    final proxies = [
      for (final p in profile.proxies) Map<String, Object?>.from(p.raw),
    ];
    if (proxies.isEmpty) {
      throw ConfigEditException('订阅的 YAML 里没有 proxies');
    }
    return SubscriptionResult(proxies: proxies, yamlConfig: text, title: title);
  }

  // base64：机场普遍把一堆链接 base64 之后返回
  if (_base64Chars.hasMatch(text)) {
    final decoded = _tryDecodeBase64(text);
    if (decoded != null && _hasScheme.hasMatch(decoded)) {
      final proxies = parseShareLinks(decoded);
      if (proxies.isNotEmpty) {
        return SubscriptionResult(proxies: proxies, title: title);
      }
    }
  }

  final proxies = parseShareLinks(text);
  if (proxies.isEmpty) {
    final head = text.length > 60 ? text.substring(0, 60) : text;
    throw ConfigEditException('订阅里没找到节点（开头是：$head…）');
  }
  return SubscriptionResult(proxies: proxies, title: title);
}

String? _tryDecodeBase64(String text) {
  final compact = text.replaceAll(RegExp(r'\s'), '');
  if (compact.length < 16) return null;
  final normalized = compact.replaceAll('-', '+').replaceAll('_', '/');
  final padded = normalized.padRight(
    normalized.length + (4 - normalized.length % 4) % 4,
    '=',
  );
  try {
    return utf8.decode(base64Decode(padded), allowMalformed: true);
  } on FormatException {
    return null;
  }
}

/// 从订阅地址拉取并解析。
///
/// 只在网络/HTTP 层面失败时抛异常；解析失败也抛 [ConfigEditException]，
/// 界面统一按"把 message 显示出来"处理。
Future<SubscriptionResult> fetchSubscription(
  String url, {
  HttpClient? client,
  Duration timeout = const Duration(seconds: 20),
  Map<String, String>? headers,
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !uri.hasScheme ||
      !uri.isScheme('http') && !uri.isScheme('https')) {
    throw ConfigEditException('不是有效的订阅地址：$url');
  }

  final owned = client == null;
  final http = client ?? HttpClient()
    ..connectionTimeout = timeout;
  try {
    final request = await http.getUrl(uri).timeout(timeout);
    request.headers.set(
      HttpHeaders.userAgentHeader,
      'ClashDeck/0.1 (+https://github.com/MetaCubeX/mihomo)',
    );
    request.headers.set(HttpHeaders.acceptHeader, '*/*');
    headers?.forEach(request.headers.set);

    final response = await request.close().timeout(timeout);
    final body = await response
        .transform(const Utf8Decoder(allowMalformed: true))
        .join()
        .timeout(timeout);

    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw ConfigEditException(
        '订阅拉取失败：HTTP ${response.statusCode}${body.isEmpty ? '' : '（${body.length > 80 ? '${body.substring(0, 80)}…' : body}）'}',
      );
    }

    final result = parseSubscriptionBody(
      body,
      title: _titleFrom(response.headers) ?? _titleFromUrl(uri),
    );
    return SubscriptionResult(
      proxies: result.proxies,
      yamlConfig: result.yamlConfig,
      title: result.title,
      usage: SubscriptionUsage.parse(
        response.headers.value('subscription-userinfo'),
      ),
    );
  } on SocketException catch (e) {
    throw ConfigEditException('连不上订阅地址：${e.message}');
  } on HttpException catch (e) {
    throw ConfigEditException('订阅请求失败：${e.message}');
  } on FormatException catch (e) {
    throw ConfigEditException('订阅地址格式不对：${e.message}');
  } finally {
    if (owned) http.close(force: true);
  }
}

String? _titleFrom(HttpHeaders headers) {
  final raw = headers.value('profile-title');
  if (raw != null && raw.trim().isNotEmpty) {
    final value = raw.trim();
    if (value.toLowerCase().startsWith('base64:')) {
      final decoded = _tryDecodeBase64(value.substring(7));
      if (decoded != null && decoded.trim().isNotEmpty) return decoded.trim();
    }
    return value;
  }
  final disposition = headers.value('content-disposition');
  if (disposition != null) {
    final match = RegExp(r'filename\*?=(?:UTF-8\x27\x27)?"?([^";]+)"?')
        .firstMatch(disposition);
    final name = match?.group(1)?.trim();
    if (name != null && name.isNotEmpty) {
      return Uri.decodeComponent(name)
          .replaceAll(RegExp(r'\.(ya?ml|txt)$'), '');
    }
  }
  return null;
}

String? _titleFromUrl(Uri uri) {
  final segment = uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
  final name = segment.replaceAll(RegExp(r'\.(ya?ml|txt)$'), '').trim();
  return name.isEmpty ? uri.host : name;
}
