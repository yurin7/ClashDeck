import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../yaml/yaml_doc.dart';

/// 拉一段纯文本（规则集、规则片段都用得上）。
///
/// 只处理网络与 HTTP 状态；内容怎么解释交给调用方。失败抛 [ConfigEditException]，
/// 界面统一显示 message。
Future<String> fetchText(
  String url, {
  HttpClient? client,
  Duration timeout = const Duration(seconds: 25),
  Map<String, String>? headers,
  int maxBytes = 16 * 1024 * 1024,
}) async {
  final uri = Uri.tryParse(url.trim());
  if (uri == null ||
      !uri.hasScheme ||
      (!uri.isScheme('http') && !uri.isScheme('https'))) {
    throw ConfigEditException('不是有效的地址：$url');
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
    if (response.statusCode < 200 || response.statusCode >= 300) {
      // 把响应体读掉，避免连接悬着。
      await response.drain<void>().catchError((_) {});
      throw ConfigEditException('拉取失败：HTTP ${response.statusCode}');
    }

    final chunks = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      chunks.addAll(chunk);
      if (chunks.length > maxBytes) {
        throw ConfigEditException('文件太大（超过 ${maxBytes ~/ 1024 ~/ 1024} MB）');
      }
    }
    return utf8.decode(chunks, allowMalformed: true);
  } on ConfigEditException {
    rethrow;
  } on TimeoutException {
    throw ConfigEditException('拉取超时（$url）');
  } on SocketException catch (e) {
    throw ConfigEditException('网络错误：${e.message}');
  } finally {
    if (owned) http.close(force: true);
  }
}
