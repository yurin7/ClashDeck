// Share-link ("subscription") parsers.
//
// Converts `vless://`, `vmess://`, `trojan://`, `ss://`, `ssr://`,
// `hysteria2://`, `tuic://` and `socks5://` / `http://` URIs into mihomo
// (Clash.Meta) `proxies` entries.
//
// The library is pure Dart and deliberately has no Flutter dependency. Every
// public entry point is total: malformed input returns `null` (or is skipped by
// [parseShareLinks]) instead of throwing.
//
// Mapping notes / ambiguities resolved here are documented next to the code
// that implements them. In particular:
//
//  * Query keys are matched case-insensitively (share links are inconsistent
//    about e.g. `allowInsecure` vs `allowinsecure`).
//  * Empty / null values are never written into the resulting map.
//  * `flow`, `encryption`, `client-fingerprint`, `alpn`, ... are only emitted
//    when the link actually carries them.
//  * `ed` / `eh` (WebSocket early data), `mode` (gRPC) and `pinSHA256` are
//    mapped onto the fields mihomo actually understands; `spx` and
//    `headerType` have no mihomo counterpart and are ignored.

import 'dart:convert';

/// Schemes recognised by [parseShareLink] and advertised to the UI.
///
/// `https://` is accepted by [parseShareLink] as an HTTP proxy with
/// `tls: true`, but it is not listed here: without an explicit port an
/// `https://` URI is far more likely to be a web page than a proxy.
const List<String> kUriSchemes = <String>[
  'vless',
  'vmess',
  'trojan',
  'ss',
  'ssr',
  'hysteria2',
  'hy2',
  'tuic',
  'socks5',
  'socks',
  'http',
];

/// Schemes supported by [parseShareLink].
List<String> get supportedSchemes => kUriSchemes;

/// Parses a single share link into a mihomo `proxies` entry.
///
/// Returns `null` for unsupported schemes, malformed input, or links that are
/// missing data mihomo requires (server / port / credentials).
Map<String, Object?>? parseShareLink(String uri) {
  if (uri.trim().isEmpty) {
    return null;
  }
  try {
    final _RawLink? raw = _splitLink(uri);
    if (raw == null) {
      return null;
    }
    switch (raw.scheme) {
      case 'vless':
        return _parseVless(raw);
      case 'vmess':
        return _parseVmess(raw);
      case 'trojan':
        return _parseTrojan(raw);
      case 'ss':
        return _parseSs(raw);
      case 'ssr':
        return _parseSsr(raw);
      case 'hysteria2':
      case 'hy2':
        return _parseHysteria2(raw);
      case 'tuic':
        return _parseTuic(raw);
      case 'socks5':
      case 'socks':
      case 'http':
      case 'https':
        return _parseSocksOrHttp(raw);
      default:
        return null;
    }
  } catch (_) {
    // A parser must never take the import screen down with it.
    return null;
  }
}

/// Parses a blob of text that may hold one link per line, or an entire
/// base64-wrapped subscription.
///
/// Successfully parsed nodes are returned in input order; unusable lines are
/// skipped. Duplicate names are made unique by appending `-2`, `-3`, ... so the
/// result can be written straight into `proxies:`.
List<Map<String, Object?>> parseShareLinks(String text) {
  final List<Map<String, Object?>> result = <Map<String, Object?>>[];
  try {
    final String expanded = _expandSubscription(text);
    final Set<String> usedNames = <String>{};
    for (final String line in expanded.split(RegExp(r'\r\n|\r|\n'))) {
      final String trimmed = line.replaceAll('\uFEFF', '').trim();
      if (trimmed.isEmpty || trimmed.startsWith('#')) {
        continue;
      }
      Map<String, Object?>? node;
      try {
        node = parseShareLink(trimmed);
      } catch (_) {
        node = null;
      }
      if (node == null) {
        continue;
      }
      final Object? rawName = node['name'];
      final String name = rawName is String ? rawName.trim() : '';
      node['name'] = _uniqueName(name.isEmpty ? 'proxy' : name, usedNames);
      result.add(node);
    }
  } catch (_) {
    return result;
  }
  return result;
}

// ---------------------------------------------------------------------------
// Text / base64 helpers
// ---------------------------------------------------------------------------

/// Splits a subscription body into lines.
///
/// When the whole body is base64 (which is how most providers ship a
/// subscription), it is decoded first. `> 32` characters keeps short base64
/// noise (e.g. a bare password) from being decoded accidentally.
String _expandSubscription(String text) {
  final String collapsed = text.replaceAll(RegExp(r'\s+'), '');
  if (collapsed.length <= 32 ||
      !RegExp(r'^[A-Za-z0-9+/=_-]+$').hasMatch(collapsed)) {
    return text;
  }
  final String? decoded = _base64Text(collapsed);
  if (decoded == null || decoded.isEmpty) {
    return text;
  }
  return decoded;
}

/// Decodes [input] as standard or URL-safe base64, with or without padding.
List<int>? _base64Bytes(String input) {
  String text = input.replaceAll(RegExp(r'\s+'), '');
  if (text.isEmpty) {
    return null;
  }
  final int remainder = text.length % 4;
  if (remainder == 1) {
    return null;
  }
  text = text.replaceAll('-', '+').replaceAll('_', '/');
  if (remainder != 0) {
    text = text.padRight(text.length + (4 - remainder), '=');
  }
  try {
    return base64.decode(text);
  } on FormatException {
    return null;
  }
}

/// Decodes [input] as base64 and then as UTF-8; `null` when either step fails.
String? _base64Text(String input) {
  final List<int>? bytes = _base64Bytes(input);
  if (bytes == null) {
    return null;
  }
  return _utf8(bytes);
}

String? _utf8(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return null;
  }
}

/// Percent-decodes [value], falling back to the raw text for malformed escapes.
String _decode(String value) {
  if (value.isEmpty) {
    return value;
  }
  try {
    return Uri.decodeComponent(value);
  } on ArgumentError {
    return value;
  } on FormatException {
    return value;
  }
}

// ---------------------------------------------------------------------------
// URI primitives
// ---------------------------------------------------------------------------

/// One raw share link split into its pieces (still percent-encoded except the
/// fragment).
class _RawLink {
  const _RawLink(this.scheme, this.head, this.query, this.fragment);

  /// Lower-case scheme, e.g. `vless`.
  final String scheme;

  /// Everything between `<scheme>://` and the first `?` or `#`.
  final String head;

  /// Raw query string (without the leading `?`).
  final String query;

  /// Percent-decoded fragment (the display name).
  final String fragment;
}

_RawLink? _splitLink(String input) {
  final String raw = input.trim();
  final int separator = raw.indexOf('://');
  if (separator <= 0) {
    return null;
  }
  final String scheme = raw.substring(0, separator).toLowerCase();
  String rest = raw.substring(separator + 3);
  String fragment = '';
  final int hash = rest.indexOf('#');
  if (hash >= 0) {
    fragment = _decode(rest.substring(hash + 1));
    rest = rest.substring(0, hash);
  }
  String query = '';
  final int question = rest.indexOf('?');
  if (question >= 0) {
    query = rest.substring(question + 1);
    rest = rest.substring(0, question);
  }
  return _RawLink(scheme, rest, query, fragment);
}

/// Decoded `userinfo@host:port` triple.
class _Authority {
  const _Authority(this.userInfo, this.host, this.port);

  final String userInfo;
  final String host;
  final int? port;
}

/// Parses `[userinfo@]host[:port]`.
///
/// The host part is what appears after the **last** `@`, which tolerates a
/// raw `@` inside a password (`user:p@ss@host:443`). A path suffix such as the
/// `/` in `vless://u@h:443/?...` is ignored.
_Authority? _parseAuthority(String head, {bool requirePort = true}) {
  final int at = head.lastIndexOf('@');
  final String rawUserInfo = at < 0 ? '' : head.substring(0, at);
  final String hostPart = at < 0 ? head : head.substring(at + 1);
  final _HostPort? hostPort = _parseHostPort(hostPart);
  if (hostPort == null) {
    return null;
  }
  if (requirePort && hostPort.port == null) {
    return null;
  }
  return _Authority(_decode(rawUserInfo), hostPort.host, hostPort.port);
}

class _HostPort {
  const _HostPort(this.host, this.port);

  final String host;
  final int? port;
}

/// Parses `host[:port]` (optionally `[ipv6][:port]`), rejecting invalid ports.
_HostPort? _parseHostPort(String raw) {
  String value = raw.trim();
  final int slash = value.indexOf('/');
  if (slash >= 0) {
    value = value.substring(0, slash);
  }
  if (value.isEmpty) {
    return null;
  }
  String host;
  String? portText;
  if (value.startsWith('[')) {
    final int close = value.indexOf(']');
    if (close < 0) {
      return null;
    }
    host = value.substring(1, close);
    final String tail = value.substring(close + 1);
    if (tail.startsWith(':')) {
      portText = tail.substring(1);
    } else if (tail.isNotEmpty) {
      return null;
    }
  } else {
    final int colon = value.lastIndexOf(':');
    if (colon >= 0) {
      host = value.substring(0, colon);
      portText = value.substring(colon + 1);
    } else {
      host = value;
    }
  }
  host = _decode(host);
  if (host.isEmpty || host.contains(' ')) {
    return null;
  }
  int? port;
  if (portText != null && portText.isNotEmpty) {
    port = int.tryParse(portText);
    if (port == null || port < 1 || port > 65535) {
      return null;
    }
  }
  return _HostPort(host, port);
}

/// Parses `a=1&b=2`; keys are lower-cased, values percent-decoded, and the
/// first occurrence of a key wins.
Map<String, String> _parseQuery(String rawQuery) {
  final Map<String, String> result = <String, String>{};
  if (rawQuery.isEmpty) {
    return result;
  }
  for (final String pair in rawQuery.split('&')) {
    if (pair.isEmpty) {
      continue;
    }
    final int equals = pair.indexOf('=');
    final String key = equals < 0 ? pair : pair.substring(0, equals);
    final String value = equals < 0 ? '' : pair.substring(equals + 1);
    final String decodedKey = _decode(key).trim().toLowerCase();
    if (decodedKey.isEmpty || result.containsKey(decodedKey)) {
      continue;
    }
    result[decodedKey] = _decode(value);
  }
  return result;
}

String _param(Map<String, String> params, String key) => params[key] ?? '';

// ---------------------------------------------------------------------------
// Value helpers
// ---------------------------------------------------------------------------

String _network(String raw) {
  final String value = raw.trim().toLowerCase();
  return value.isEmpty ? 'tcp' : value;
}

String _string(Object? value) => value == null ? '' : value.toString().trim();

int? _toInt(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is int) {
    return value;
  }
  if (value is num) {
    return value.toInt();
  }
  return int.tryParse(value.toString().trim());
}

/// `1` / `true` / `yes` (and their `bool` / numeric equivalents) are truthy.
bool _truthy(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  if (value is num) {
    return value != 0;
  }
  final String text = value.toString().trim().toLowerCase();
  return text == '1' || text == 'true' || text == 'yes';
}

List<String>? _alpnValues(String raw) {
  if (raw.trim().isEmpty) {
    return null;
  }
  final List<String> values = <String>[];
  for (final String part in raw.split(',')) {
    final String trimmed = part.trim();
    if (trimmed.isNotEmpty) {
      values.add(trimmed);
    }
  }
  return values.isEmpty ? null : values;
}

List<String>? _alpnFromJson(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is List) {
    final List<String> values = <String>[];
    for (final Object? item in value) {
      if (item == null) {
        continue;
      }
      final String text = item.toString().trim();
      if (text.isNotEmpty) {
        values.add(text);
      }
    }
    return values.isEmpty ? null : values;
  }
  return _alpnValues(value.toString());
}

/// Comma-separated host list used by the `h2` / `http` transport options.
List<String> _hostList(String raw) {
  final List<String> hosts = <String>[];
  for (final String part in raw.split(',')) {
    final String trimmed = part.trim();
    if (trimmed.isNotEmpty) {
      hosts.add(trimmed);
    }
  }
  return hosts;
}

String _displayName(
  _RawLink raw,
  String host,
  int port, {
  String preferred = '',
}) {
  if (preferred.isNotEmpty) {
    return preferred;
  }
  final String fragment = raw.fragment.trim();
  if (fragment.isNotEmpty) {
    return fragment;
  }
  return '$host:$port';
}

void _putText(Map<String, Object?> proxy, String key, String value) {
  if (value.isNotEmpty) {
    proxy[key] = value;
  }
}

void _putAlpn(Map<String, Object?> proxy, List<String>? alpn) {
  if (alpn != null && alpn.isNotEmpty) {
    proxy['alpn'] = alpn;
  }
}

bool _insecureFromParams(Map<String, String> params) {
  return _truthy(_param(params, 'allowinsecure')) ||
      _truthy(_param(params, 'allow_insecure')) ||
      _truthy(_param(params, 'insecure')) ||
      _truthy(_param(params, 'skip-cert-verify'));
}

// ---------------------------------------------------------------------------
// Transport option builders
// ---------------------------------------------------------------------------

/// `ws-opts` for WebSocket / HTTPUpgrade transports.
Map<String, Object?> _wsOpts({
  required String path,
  required String host,
  bool httpUpgrade = false,
  Map<String, Object?> extra = const <String, Object?>{},
}) {
  final Map<String, Object?> opts = <String, Object?>{};
  opts['path'] = path.isEmpty ? '/' : path;
  if (host.isNotEmpty) {
    opts['headers'] = <String, Object?>{'Host': host};
  }
  if (httpUpgrade) {
    opts['v2ray-http-upgrade'] = true;
  }
  for (final MapEntry<String, Object?> entry in extra.entries) {
    opts[entry.key] = entry.value;
  }
  return opts;
}

/// WebSocket early data (`ed` / `eh`, as used by Cloudflare-fronted nodes).
Map<String, Object?> _earlyData(Map<String, String> params) {
  final Map<String, Object?> extra = <String, Object?>{};
  final int? maxEarlyData = _toInt(_param(params, 'ed'));
  if (maxEarlyData != null && maxEarlyData > 0) {
    extra['max-early-data'] = maxEarlyData;
  }
  final String earlyDataHeader = _param(params, 'eh');
  if (earlyDataHeader.isNotEmpty) {
    extra['early-data-header-name'] = earlyDataHeader;
  }
  return extra;
}

/// `grpc-opts`; `mode` is only emitted when the link supplies one.
Map<String, Object?>? _grpcOpts(String serviceName, String mode) {
  if (serviceName.isEmpty && mode.isEmpty) {
    return null;
  }
  final Map<String, Object?> opts = <String, Object?>{};
  if (serviceName.isNotEmpty) {
    opts['grpc-service-name'] = serviceName;
  }
  if (mode.isNotEmpty) {
    opts['grpc-mode'] = mode;
  }
  return opts;
}

/// `http-opts` — mihomo expects `path` and `Host` to be string lists.
Map<String, Object?> _httpOpts(String path, String host) {
  final List<String> paths = _hostList(path);
  if (paths.isEmpty) {
    paths.add('/');
  }
  final Map<String, Object?> opts = <String, Object?>{'path': paths};
  final List<String> hosts = _hostList(host);
  if (hosts.isNotEmpty) {
    opts['headers'] = <String, Object?>{'Host': hosts};
  }
  return opts;
}

/// `h2-opts`; omitted entirely when the link carries neither host nor path.
Map<String, Object?>? _h2Opts(String host, String path) {
  final Map<String, Object?> opts = <String, Object?>{};
  final List<String> hosts = _hostList(host);
  if (hosts.isNotEmpty) {
    opts['host'] = hosts;
  }
  if (path.isNotEmpty) {
    opts['path'] = path;
  }
  return opts.isEmpty ? null : opts;
}

// ---------------------------------------------------------------------------
// vless://
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseVless(_RawLink raw) {
  final _Authority? authority = _parseAuthority(raw.head);
  if (authority == null ||
      authority.userInfo.isEmpty ||
      authority.port == null) {
    return null;
  }
  final Map<String, String> params = _parseQuery(raw.query);
  final String security = _param(params, 'security').toLowerCase();
  final bool tls =
      security == 'tls' || security == 'reality' || security == 'xtls';
  final String network = _network(_param(params, 'type'));
  final int port = authority.port!;

  final Map<String, Object?> proxy = <String, Object?>{
    'name': _displayName(raw, authority.host, port),
    'type': 'vless',
    'server': authority.host,
    'port': port,
    'uuid': authority.userInfo,
    'network': network,
    'udp': true,
    'tls': tls,
  };

  final String fingerprint = _param(params, 'fp');
  if (fingerprint.isNotEmpty) {
    proxy['client-fingerprint'] = fingerprint;
  }
  final String sni = _param(params, 'sni');
  if (tls && sni.isNotEmpty) {
    proxy['servername'] = sni;
  }
  _putText(proxy, 'flow', _param(params, 'flow'));
  _putText(proxy, 'encryption', _param(params, 'encryption'));
  _putAlpn(proxy, _alpnValues(_param(params, 'alpn')));
  if (_insecureFromParams(params)) {
    proxy['skip-cert-verify'] = true;
  }
  if (security == 'reality') {
    // Without a public key mihomo cannot handshake, so an incomplete
    // reality-opts block is worse than none: keep the node, drop the block.
    final String publicKey = _param(params, 'pbk');
    if (publicKey.isNotEmpty) {
      final Map<String, Object?> reality = <String, Object?>{
        'public-key': publicKey,
      };
      final String shortId = _param(params, 'sid');
      if (shortId.isNotEmpty) {
        reality['short-id'] = shortId;
      }
      proxy['reality-opts'] = reality;
    }
  }

  final String path = _param(params, 'path');
  final String host = _param(params, 'host');
  if (network == 'ws') {
    proxy['ws-opts'] = _wsOpts(
      path: path,
      host: host,
      extra: _earlyData(params),
    );
  } else if (network == 'httpupgrade') {
    proxy['ws-opts'] = _wsOpts(
      path: path,
      host: host,
      httpUpgrade: true,
      extra: _earlyData(params),
    );
  } else if (network == 'grpc') {
    final Map<String, Object?>? grpc = _grpcOpts(
      _param(params, 'servicename'),
      _param(params, 'mode'),
    );
    if (grpc != null) {
      proxy['grpc-opts'] = grpc;
    }
  } else if (network == 'http') {
    proxy['http-opts'] = _httpOpts(path, host);
  } else if (network == 'h2') {
    final Map<String, Object?>? h2 = _h2Opts(host, path);
    if (h2 != null) {
      proxy['h2-opts'] = h2;
    }
  }
  return proxy;
}

// ---------------------------------------------------------------------------
// vmess://
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseVmess(_RawLink raw) {
  final String? text = _base64Text(raw.head);
  if (text == null) {
    return null;
  }
  Object? decoded;
  try {
    decoded = jsonDecode(text);
  } on FormatException {
    return null;
  }
  if (decoded is! Map) {
    return null;
  }
  final Map<Object?, Object?> json = decoded;

  // 少数客户端/面板用短键 `t`/`p`（而不是 `add`/`port`）；两个都认，
  // 否则整条节点会被静默跳过（实测就踩到过：解析出 2 个而不是 3 个）。
  final String server = _string(json['add'] ?? json['t']);
  final int? port = _toInt(json['port'] ?? json['p']);
  if (server.isEmpty || port == null || port < 1 || port > 65535) {
    return null;
  }
  final String uuid = _string(json['id']);
  if (uuid.isEmpty) {
    return null;
  }

  final String network = _network(_string(json['net']));
  final Object? rawTls = json['tls'];
  final String tlsMode = _string(rawTls).toLowerCase();
  final bool tls =
      rawTls == true ||
      tlsMode == 'tls' ||
      tlsMode == 'reality' ||
      tlsMode == 'xtls';
  final String cipher = _string(json['scy']);
  final String name = _string(json['ps']);

  final Map<String, Object?> proxy = <String, Object?>{
    'name': _displayName(raw, server, port, preferred: name),
    'type': 'vmess',
    'server': server,
    'port': port,
    'uuid': uuid,
    'alterId': _toInt(json['aid']) ?? 0,
    'cipher': cipher.isEmpty ? 'auto' : cipher,
    'network': network,
    'udp': true,
    'tls': tls,
  };

  _putText(proxy, 'servername', _string(json['sni']));
  _putAlpn(proxy, _alpnFromJson(json['alpn']));
  _putText(proxy, 'client-fingerprint', _string(json['fp']));
  if (_truthy(json['allowInsecure']) ||
      _truthy(json['skip-cert-verify']) ||
      _truthy(json['insecure'])) {
    proxy['skip-cert-verify'] = true;
  }

  final String path = _string(json['path']);
  final String host = _string(json['host']);
  if (network == 'ws') {
    proxy['ws-opts'] = _wsOpts(path: path, host: host);
  } else if (network == 'grpc') {
    final Map<String, Object?>? grpc = _grpcOpts(path, '');
    if (grpc != null) {
      proxy['grpc-opts'] = grpc;
    }
  } else if (network == 'h2') {
    final Map<String, Object?>? h2 = _h2Opts(host, path);
    if (h2 != null) {
      proxy['h2-opts'] = h2;
    }
  }
  return proxy;
}

// ---------------------------------------------------------------------------
// trojan://
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseTrojan(_RawLink raw) {
  final _Authority? authority = _parseAuthority(raw.head);
  if (authority == null ||
      authority.userInfo.isEmpty ||
      authority.port == null) {
    return null;
  }
  final Map<String, String> params = _parseQuery(raw.query);
  final String network = _network(_param(params, 'type'));
  final int port = authority.port!;

  final Map<String, Object?> proxy = <String, Object?>{
    'name': _displayName(raw, authority.host, port),
    'type': 'trojan',
    'server': authority.host,
    'port': port,
    'password': authority.userInfo,
    'udp': true,
    'network': network,
  };

  // Trojan uses `sni`; some exporters write `peer` instead.
  String sni = _param(params, 'sni');
  if (sni.isEmpty) {
    sni = _param(params, 'peer');
  }
  _putText(proxy, 'sni', sni);
  if (_insecureFromParams(params)) {
    proxy['skip-cert-verify'] = true;
  }
  _putAlpn(proxy, _alpnValues(_param(params, 'alpn')));
  _putText(proxy, 'client-fingerprint', _param(params, 'fp'));

  final String path = _param(params, 'path');
  final String host = _param(params, 'host');
  if (network == 'ws') {
    proxy['ws-opts'] = _wsOpts(path: path, host: host);
  } else if (network == 'grpc') {
    final Map<String, Object?>? grpc = _grpcOpts(
      _param(params, 'servicename'),
      _param(params, 'mode'),
    );
    if (grpc != null) {
      proxy['grpc-opts'] = grpc;
    }
  }
  return proxy;
}

// ---------------------------------------------------------------------------
// ss://
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseSs(_RawLink raw) {
  String head = raw.head;
  if (head.isEmpty) {
    return null;
  }
  String cipher;
  String password;
  String hostPart;
  final int at = head.lastIndexOf('@');
  if (at >= 0) {
    // SIP002: ss://base64(method:password)@host:port
    final String userInfo = head.substring(0, at);
    hostPart = head.substring(at + 1);
    final String? decoded = _base64Text(userInfo);
    if (decoded != null && decoded.contains(':')) {
      final int colon = decoded.indexOf(':');
      cipher = decoded.substring(0, colon).trim();
      password = decoded.substring(colon + 1);
    } else {
      // Some exporters percent-encode a plain `method:password` instead.
      final String plain = _decode(userInfo);
      final int colon = plain.indexOf(':');
      if (colon < 0) {
        return null;
      }
      cipher = plain.substring(0, colon).trim();
      password = plain.substring(colon + 1);
    }
  } else {
    // Legacy: ss://base64(method:password@host:port)
    String body = head;
    String? decoded = _base64Text(body);
    if (decoded == null && body.endsWith('/')) {
      body = body.substring(0, body.length - 1);
      decoded = _base64Text(body);
    }
    if (decoded == null) {
      return null;
    }
    final int legacyAt = decoded.lastIndexOf('@');
    if (legacyAt < 0) {
      return null;
    }
    final String userInfo = decoded.substring(0, legacyAt);
    hostPart = decoded.substring(legacyAt + 1);
    final int colon = userInfo.indexOf(':');
    if (colon < 0) {
      return null;
    }
    cipher = userInfo.substring(0, colon).trim();
    password = userInfo.substring(colon + 1);
  }
  if (cipher.isEmpty) {
    return null;
  }
  final _HostPort? hostPort = _parseHostPort(hostPart);
  if (hostPort == null || hostPort.port == null) {
    return null;
  }
  final int port = hostPort.port!;

  final Map<String, Object?> proxy = <String, Object?>{
    'name': _displayName(raw, hostPort.host, port),
    'type': 'ss',
    'server': hostPort.host,
    'port': port,
    'cipher': cipher,
    'password': password,
    'udp': true,
  };

  final Map<String, String> params = _parseQuery(raw.query);
  final String plugin = _param(params, 'plugin');
  if (plugin.isNotEmpty) {
    final Map<String, Object?>? pluginConfig = _ssPlugin(plugin);
    if (pluginConfig == null) {
      // A plugin mihomo cannot emulate would silently change how the node
      // behaves, so the node is dropped instead.
      return null;
    }
    proxy['plugin'] = pluginConfig['plugin'];
    proxy['plugin-opts'] = pluginConfig['plugin-opts'];
  }
  return proxy;
}

/// Converts a SIP003 plugin string (`obfs-local;obfs=http;obfs-host=x`) into
/// mihomo's `plugin` / `plugin-opts` pair; `null` for unknown plugins.
Map<String, Object?>? _ssPlugin(String raw) {
  final List<String> parts = raw.split(';');
  final String name = parts.first.trim().toLowerCase();
  final Map<String, String> options = <String, String>{};
  for (final String part in parts.skip(1)) {
    final int equals = part.indexOf('=');
    if (equals < 0) {
      // A bare flag, e.g. `;tls`.
      final String flag = part.trim().toLowerCase();
      if (flag.isNotEmpty) {
        options[flag] = '';
      }
      continue;
    }
    options[part.substring(0, equals).trim().toLowerCase()] = part
        .substring(equals + 1)
        .trim();
  }
  if (name == 'obfs-local' || name == 'simple-obfs' || name == 'obfs') {
    String mode = options['obfs'] ?? options['mode'] ?? 'http';
    if (mode.isEmpty) {
      mode = 'http';
    }
    final Map<String, Object?> opts = <String, Object?>{'mode': mode};
    final String host = options['obfs-host'] ?? options['host'] ?? '';
    if (host.isNotEmpty) {
      opts['host'] = host;
    }
    return <String, Object?>{'plugin': 'obfs', 'plugin-opts': opts};
  }
  if (name == 'v2ray-plugin') {
    String mode = options['mode'] ?? 'websocket';
    if (mode.isEmpty) {
      mode = 'websocket';
    }
    final Map<String, Object?> opts = <String, Object?>{'mode': mode};
    final String host = options['host'] ?? '';
    if (host.isNotEmpty) {
      opts['host'] = host;
    }
    final String path = options['path'] ?? '';
    if (path.isNotEmpty) {
      opts['path'] = path;
    }
    if (options.containsKey('tls')) {
      opts['tls'] = true;
    }
    return <String, Object?>{'plugin': 'v2ray-plugin', 'plugin-opts': opts};
  }
  return null;
}

// ---------------------------------------------------------------------------
// hysteria2:// (hy2://)
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseHysteria2(_RawLink raw) {
  final _Authority? authority = _parseAuthority(raw.head);
  if (authority == null || authority.port == null) {
    return null;
  }
  final Map<String, String> params = _parseQuery(raw.query);
  final int port = authority.port!;

  final Map<String, Object?> proxy = <String, Object?>{
    'name': _displayName(raw, authority.host, port),
    'type': 'hysteria2',
    'server': authority.host,
    'port': port,
  };
  // Hysteria2 servers may be configured without auth.
  _putText(proxy, 'password', authority.userInfo);

  String sni = _param(params, 'sni');
  if (sni.isEmpty) {
    sni = _param(params, 'peer');
  }
  _putText(proxy, 'sni', sni);
  if (_insecureFromParams(params)) {
    proxy['skip-cert-verify'] = true;
  }
  _putText(proxy, 'obfs', _param(params, 'obfs'));
  _putText(proxy, 'obfs-password', _param(params, 'obfs-password'));
  _putAlpn(proxy, _alpnValues(_param(params, 'alpn')));
  // mihomo pins certificates through `fingerprint`.
  _putText(proxy, 'fingerprint', _param(params, 'pinsha256'));
  // `mport` is a port-hopping range/list in mihomo's `ports` field.
  _putText(proxy, 'ports', _param(params, 'mport'));
  return proxy;
}

// ---------------------------------------------------------------------------
// tuic://
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseTuic(_RawLink raw) {
  final _Authority? authority = _parseAuthority(raw.head);
  if (authority == null ||
      authority.userInfo.isEmpty ||
      authority.port == null) {
    return null;
  }
  final String userInfo = authority.userInfo;
  final int colon = userInfo.indexOf(':');
  if (colon <= 0) {
    return null;
  }
  final Map<String, String> params = _parseQuery(raw.query);
  final int port = authority.port!;

  final Map<String, Object?> proxy = <String, Object?>{
    'name': _displayName(raw, authority.host, port),
    'type': 'tuic',
    'server': authority.host,
    'port': port,
    'uuid': userInfo.substring(0, colon),
  };
  // The password may legitimately contain further colons.
  _putText(proxy, 'password', userInfo.substring(colon + 1));

  _putText(
    proxy,
    'congestion-controller',
    _param(params, 'congestion_control'),
  );
  _putAlpn(proxy, _alpnValues(_param(params, 'alpn')));
  _putText(proxy, 'sni', _param(params, 'sni'));
  if (_insecureFromParams(params)) {
    proxy['skip-cert-verify'] = true;
  }
  _putText(proxy, 'udp-relay-mode', _param(params, 'udp_relay_mode'));
  return proxy;
}

// ---------------------------------------------------------------------------
// socks5:// / socks:// / http:// / https://
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseSocksOrHttp(_RawLink raw) {
  // No port means this is very likely a web URL, not a proxy definition.
  final _Authority? authority = _parseAuthority(raw.head);
  if (authority == null || authority.port == null) {
    return null;
  }
  final bool isHttp = raw.scheme == 'http' || raw.scheme == 'https';
  final int port = authority.port!;
  final Map<String, Object?> proxy = <String, Object?>{
    'name': _displayName(raw, authority.host, port),
    'type': isHttp ? 'http' : 'socks5',
    'server': authority.host,
    'port': port,
  };
  if (raw.scheme == 'https') {
    proxy['tls'] = true;
  }

  final String userInfo = authority.userInfo;
  if (userInfo.isNotEmpty) {
    final int colon = userInfo.indexOf(':');
    if (colon >= 0) {
      _putText(proxy, 'username', userInfo.substring(0, colon));
      _putText(proxy, 'password', userInfo.substring(colon + 1));
    } else {
      proxy['username'] = userInfo;
    }
  }
  return proxy;
}

// ---------------------------------------------------------------------------
// ssr://
// ---------------------------------------------------------------------------

Map<String, Object?>? _parseSsr(_RawLink raw) {
  final String? decoded = _base64Text(raw.head);
  if (decoded == null || decoded.isEmpty) {
    return null;
  }
  String main = decoded;
  String paramText = '';
  final int slashQuery = decoded.indexOf('/?');
  if (slashQuery >= 0) {
    main = decoded.substring(0, slashQuery);
    paramText = decoded.substring(slashQuery + 2);
  } else {
    final int question = decoded.indexOf('?');
    if (question >= 0) {
      main = decoded.substring(0, question);
      paramText = decoded.substring(question + 1);
    }
  }

  // host:port:protocol:method:obfs:base64(password)
  final List<String> fields = main.split(':');
  if (fields.length < 6) {
    return null;
  }
  final String host = fields[0].trim();
  final int? port = int.tryParse(fields[1].trim());
  final String protocol = fields[2].trim();
  final String method = fields[3].trim();
  final String obfs = fields[4].trim();
  final String passwordRaw = fields.sublist(5).join(':').trim();
  if (host.isEmpty || port == null || port < 1 || port > 65535) {
    return null;
  }
  if (method.isEmpty) {
    return null;
  }
  final String password = _base64Text(passwordRaw) ?? passwordRaw;

  final Map<String, String> params = _parseQuery(paramText);
  String name = '';
  final String remarks = _param(params, 'remarks');
  if (remarks.isNotEmpty) {
    name = _base64Text(remarks) ?? remarks;
  }

  final Map<String, Object?> proxy = <String, Object?>{
    'name': name.isNotEmpty ? name : '$host:$port',
    'type': 'ssr',
    'server': host,
    'port': port,
    'cipher': method,
    'password': password,
    'protocol': protocol.isEmpty ? 'origin' : protocol,
    'obfs': obfs.isEmpty ? 'plain' : obfs,
  };
  final String protocolParam = _decodeSsrParam(
    _param(params, 'protocol-param'),
  );
  if (protocolParam.isNotEmpty) {
    proxy['protocol-param'] = protocolParam;
  }
  final String obfsParam = _decodeSsrParam(_param(params, 'obfs-param'));
  if (obfsParam.isNotEmpty) {
    proxy['obfs-param'] = obfsParam;
  }
  return proxy;
}

String _decodeSsrParam(String raw) {
  if (raw.isEmpty) {
    return raw;
  }
  return _base64Text(raw) ?? raw;
}

// ---------------------------------------------------------------------------
// Name de-duplication
// ---------------------------------------------------------------------------

String _uniqueName(String base, Set<String> used) {
  String candidate = base;
  if (used.contains(candidate)) {
    int index = 2;
    while (used.contains('$base-$index')) {
      index++;
    }
    candidate = '$base-$index';
  }
  used.add(candidate);
  return candidate;
}
