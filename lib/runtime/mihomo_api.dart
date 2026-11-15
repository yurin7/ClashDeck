import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// mihomo（Clash Meta）RESTful API 的最小客户端。
///
/// 只依赖 `dart:io`，不依赖 Flutter，方便在纯 Dart 测试里跑。
/// 对应内核的 `external-controller`：默认 `127.0.0.1:9090`。
///
/// 注意：这个 API **不能**增删节点或改规则——那部分由配置文件编辑器负责，
/// 改完配置后调用 [reloadConfig] 让内核热重载。
class MihomoApi {
  MihomoApi({
    this.host = '127.0.0.1',
    this.port = 9090,
    this.secret,
    HttpClient? client,
    this.timeout = const Duration(seconds: 8),
  }) : _client = client ?? HttpClient() {
    _client.connectionTimeout = timeout;
  }

  final String host;
  final int port;
  final String? secret;
  final Duration timeout;
  final HttpClient _client;

  Uri _uri(String path, [Map<String, String>? query]) => Uri(
    scheme: 'http',
    host: host,
    port: port,
    path: path,
    queryParameters: query,
  );

  Map<String, String> get _headers => {
    'Content-Type': 'application/json',
    if (secret != null && secret!.isNotEmpty) 'Authorization': 'Bearer $secret',
  };

  Future<Object?> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final req = await _client
        .openUrl(method, _uri(path, query))
        .timeout(timeout);
    _headers.forEach(req.headers.set);
    if (body != null) {
      final bytes = utf8.encode(jsonEncode(body));
      req.headers.contentLength = bytes.length;
      req.add(bytes);
    }
    final res = await req.close().timeout(timeout);
    final text = await res.transform(utf8.decoder).join().timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MihomoApiException(
        res.statusCode,
        text.isEmpty ? res.reasonPhrase : text,
      );
    }
    if (text.trim().isEmpty) return null;
    try {
      return jsonDecode(text);
    } on FormatException {
      return text;
    }
  }

  Future<Map<String, Object?>> _map(
    String method,
    String path, {
    Map<String, String>? query,
    Object? body,
  }) async {
    final res = await _send(method, path, query: query, body: body);
    return res is Map ? res.cast<String, Object?>() : <String, Object?>{};
  }

  // ------------------------------------------------------------ 基础信息

  /// `GET /version` —— 同时也是"内核起来了没"的探针。
  Future<Map<String, Object?>> version() => _map('GET', '/version');

  Future<bool> ping() async {
    try {
      await version();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ------------------------------------------------------------ 配置热重载

  /// `PUT /configs?force=true`，body 用 `{"path":"","payload":""}`
  /// 表示"重启当前配置文件"。改完 YAML 后调用即可生效。
  Future<void> reloadConfig({bool force = true}) async {
    await _send(
      'PUT',
      '/configs',
      query: {'force': '$force'},
      body: {'path': '', 'payload': ''},
    );
  }

  /// 只用 payload 覆盖运行配置（不落盘），用于临时试配置。
  Future<void> loadPayload(String yaml, {bool force = true}) async {
    await _send(
      'PUT',
      '/configs',
      query: {'force': '$force'},
      body: {'path': '', 'payload': yaml},
    );
  }

  /// `PATCH /configs` —— 只能改少数几个运行期开关。
  Future<void> patchConfigs(Map<String, Object?> patch) async {
    await _send('PATCH', '/configs', body: patch);
  }

  Future<Map<String, Object?>> configs() => _map('GET', '/configs');

  Future<void> setMode(String mode) => patchConfigs({'mode': mode});

  // ------------------------------------------------------------ 代理/策略组

  /// `/proxies` 的节点表：`名字 -> {type, now, all, history, ...}`。
  ///
  /// 内核返回的是 `{"proxies": {...}}`，这里把外层壳剥掉，调用方直接拿到节点表。
  Future<Map<String, Object?>> proxies() async {
    final body = await _map('GET', '/proxies');
    final inner = body['proxies'];
    return inner is Map ? inner.cast<String, Object?>() : body;
  }

  /// 强类型的节点表；没有具体字段的条目（理论上不会有）被丢弃。
  Future<Map<String, Map<String, Object?>>> proxyMap() async {
    final raw = await proxies();
    final out = <String, Map<String, Object?>>{};
    raw.forEach((key, value) {
      if (value is Map) out[key] = value.cast<String, Object?>();
    });
    return out;
  }

  /// 选择策略组里的节点：`PUT /proxies/{group}`，body `{"name": "节点"}`。
  Future<void> selectProxy(String group, String name) async {
    await _send(
      'PUT',
      '/proxies/${Uri.encodeComponent(group)}',
      body: {'name': name},
    );
  }

  /// 单节点延迟测试；[timeoutMs] 传 0 表示用内核默认。
  Future<int?> delay(
    String name, {
    String url = 'https://www.gstatic.com/generate_204',
    int? timeoutMs,
  }) async {
    final res = await _send(
      'GET',
      '/proxies/${Uri.encodeComponent(name)}/delay',
      query: {'url': url, 'timeout': '${timeoutMs ?? 5000}'},
    );
    if (res is Map) {
      final d = res['delay'];
      return d is num ? d.toInt() : null;
    }
    return null;
  }

  // ------------------------------------------------------------ 连接

  Future<Map<String, Object?>> connections() => _map('GET', '/connections');

  Future<void> closeConnection(String id) async {
    await _send('DELETE', '/connections/${Uri.encodeComponent(id)}');
  }

  Future<void> closeAllConnections() async {
    await _send('DELETE', '/connections');
  }

  // ------------------------------------------------------------ 规则/提供者

  Future<List<Object?>> rules() async {
    final res = await _send('GET', '/rules');
    if (res is Map && res['rules'] is List) {
      return (res['rules'] as List).cast<Object?>();
    }
    return const [];
  }

  Future<Map<String, Object?>> providers(String kind) =>
      _map('GET', '/providers/$kind');

  /// 更新某个 provider（订阅/规则集）：`PUT /providers/{kind}/{name}`。
  Future<void> updateProvider(String kind, String name) async {
    await _send('PUT', '/providers/$kind/${Uri.encodeComponent(name)}');
  }

  Future<Map<String, Object?>> memory() => _map('GET', '/memory');

  // ------------------------------------------------------------ 流式接口

  /// `/traffic`、`/logs`、`/memory` 之类的流式接口，按行返回 JSON 文本。
  Stream<String> stream(String path, {Map<String, String>? query}) async* {
    final req = await _client
        .openUrl('GET', _uri(path, query))
        .timeout(timeout);
    _headers.forEach(req.headers.set);
    final res = await req.close().timeout(timeout);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw MihomoApiException(res.statusCode, res.reasonPhrase);
    }
    yield* res
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .where((line) => line.trim().isNotEmpty);
  }

  /// 解析 `/traffic` 流：`{up, down}`（单位 B/s）。
  Stream<({int up, int down})> traffic() async* {
    await for (final line in stream('/traffic')) {
      final decoded = jsonDecode(line);
      if (decoded is Map) {
        final up = decoded['up'];
        final down = decoded['down'];
        yield (
          up: up is num ? up.toInt() : 0,
          down: down is num ? down.toInt() : 0,
        );
      }
    }
  }

  void close() => _client.close(force: true);
}

class MihomoApiException implements Exception {
  MihomoApiException(this.statusCode, this.message);

  final int statusCode;
  final String message;

  @override
  String toString() => 'MihomoApiException($statusCode): $message';
}
