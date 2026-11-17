import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../yaml/yaml_doc.dart';
import 'github_mirror.dart';

/// 一次成功的镜像拉取结果。
class FetchedText {
  const FetchedText(this.text, this.url);

  final String text;

  /// 实际成功的地址（可能是镜像），写进 YAML 时要用它。
  final String url;
}

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

/// 按镜像链拉文本：GitHub raw → jsdelivr → ghproxy，每个镜像最多试
/// [attemptsPerMirror] 次（HTTP 4xx 直接换下一个镜像，不浪费重试）。
///
/// 全部失败时抛 [ConfigEditException]，message 里带失败原因分类，界面直接显示。
Future<FetchedText> fetchTextWithMirrors(
  String url, {
  HttpClient? client,
  Duration timeout = const Duration(seconds: 15),
  int attemptsPerMirror = 2,
  int maxBytes = 16 * 1024 * 1024,
}) async {
  final errors = <String>[];
  for (final candidate in GithubMirror.candidates(url)) {
    final host = Uri.tryParse(candidate)?.host ?? candidate;
    for (var attempt = 0; attempt < attemptsPerMirror; attempt++) {
      try {
        final text = await fetchText(
          candidate,
          client: client,
          timeout: timeout,
          maxBytes: maxBytes,
        );
        return FetchedText(text, candidate);
      } on ConfigEditException catch (e) {
        errors.add('$host ${_classifyFetchError(e.message)}');
        if (e.message.contains('HTTP 4')) break;
      }
    }
  }
  throw ConfigEditException('拉取失败（${_summarizeFetchErrors(errors)}）');
}

String _classifyFetchError(String message) {
  if (message.contains('超时')) return '超时';
  if (message.contains('HTTP ')) {
    final code = RegExp(r'HTTP (\d{3})').firstMatch(message)?.group(1);
    return code == null ? 'HTTP 错误' : 'HTTP $code';
  }
  if (message.toLowerCase().contains('certificate') ||
      message.contains('TLS') ||
      message.contains('Handshake')) {
    return 'TLS 失败';
  }
  if (message.contains('网络错误')) return '网络不通';
  if (message.contains('太大')) return '文件过大';
  return '其他';
}

/// 把多个镜像的错误合成一句人能读的原因（同一类只报次数）。
String _summarizeFetchErrors(List<String> errors) {
  if (errors.isEmpty) return '未知原因';
  final counts = <String, int>{};
  for (final error in errors) {
    final parts = error.split(' ');
    final reason = parts.length > 1 ? parts.sublist(1).join(' ') : error;
    counts[reason] = (counts[reason] ?? 0) + 1;
  }
  final parts = [
    for (final entry in counts.entries) '${entry.key} ×${entry.value}',
  ];
  return parts.join('，');
}
