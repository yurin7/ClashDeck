import 'dart:async';
import 'dart:collection';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import 'mihomo_api.dart';
import 'runtime_controller.dart';

class WindowsConnection {
  WindowsConnection._(
    Map<dynamic, dynamic> data,
    WindowsConnection? previous,
    Duration elapsed,
    Set<String> groupNames,
  ) : id = data['id'] as String,
      downloaded = _bytes(data['download']),
      uploaded = _bytes(data['upload']),
      startedAt = DateTime.tryParse(_text(data['start'])) {
    final chain = data['chains'];
    chains = chain is List
        ? List.unmodifiable(chain.whereType<String>().toList().reversed)
        : const [];
    final metadata = data['metadata'];
    final meta = metadata is Map ? metadata : const {};
    final host = _firstText([
      meta['host'],
      meta['sniffHost'],
      meta['destinationIP'],
    ]);
    destination = _endpoint(host, _text(meta['destinationPort']));
    source = _endpoint(_text(meta['sourceIP']), _text(meta['sourcePort']));
    transport = _text(meta['network']).toUpperCase();
    processPath = _text(meta['processPath']);
    final executable = _firstText([processPath, meta['process']]);
    process = executable.split(RegExp(r'[/\\]')).last;
    rule = [
      _text(data['rule']),
      _text(data['rulePayload']),
    ].where((part) => part.isNotEmpty).join(' · ');
    groups = Set.unmodifiable(chains.where(groupNames.contains));
    downRate = _rate(downloaded, previous?.downloaded, elapsed);
    upRate = _rate(uploaded, previous?.uploaded, elapsed);
    searchText = [
      destination,
      source,
      transport,
      process,
      processPath,
      rule,
      ...chains,
    ].join(' ').toLowerCase();
  }

  final String id;
  final int downloaded;
  final int uploaded;
  final DateTime? startedAt;
  late final List<String> chains;
  late final Set<String> groups;
  late final String destination;
  late final String source;
  late final String transport;
  late final String process;
  late final String processPath;
  late final String rule;
  late final int? downRate;
  late final int? upRate;
  late final String searchText;

  String get processKey => process.toLowerCase();

  bool matches({
    required String keyword,
    String? group,
    String? executable,
    String? matchedRule,
  }) =>
      (group == null || groups.contains(group)) &&
      (executable == null || processKey == executable) &&
      (matchedRule == null || rule == matchedRule) &&
      searchText.contains(keyword);

  static int _bytes(Object? value) => value is num ? value.toInt() : 0;
  static String _text(Object? value) => value?.toString().trim() ?? '';
  static String _firstText(List<Object?> values) => values
      .map(_text)
      .firstWhere((value) => value.isNotEmpty, orElse: () => '');

  static String _endpoint(String host, String port) {
    if (host.isEmpty) return '—';
    if (port.isEmpty || port == '0') return host;
    return host.contains(':') ? '[$host]:$port' : '$host:$port';
  }

  static int? _rate(int current, int? last, Duration elapsed) {
    if (last == null || elapsed.inMicroseconds <= 0) return null;
    return (math.max(0, current - last) * 1000000 / elapsed.inMicroseconds)
        .round();
  }
}

/// The controller reports only open sockets. Remember recently observed ones
/// when they disappear, with the last sampled byte counts.
class WindowsConnectionHistory {
  static const closedLimit = 500;
  Map<String, WindowsConnection> _open = {};
  final _closed = ListQueue<WindowsConnection>();
  Duration? _sampledAt;

  int downloaded = 0;
  int uploaded = 0;

  Iterable<WindowsConnection> get open => _open.values;
  Iterable<WindowsConnection> get closed => _closed;

  void apply(
    Map<String, Object?> snapshot, {
    required Duration at,
    required Set<String> groupNames,
  }) {
    final samples = snapshot['connections'];
    final elapsed = at - (_sampledAt ?? at);
    final next = <String, WindowsConnection>{};
    if (samples is List) {
      for (final data in samples.whereType<Map>()) {
        final id = data['id'];
        if (id is! String || id.isEmpty) continue;
        next[id] = WindowsConnection._(data, _open[id], elapsed, groupNames);
      }
    }
    _archive(_open.values.where((old) => !next.containsKey(old.id)));
    _open = next;
    _sampledAt = at;
    downloaded = WindowsConnection._bytes(snapshot['downloadTotal']);
    uploaded = WindowsConnection._bytes(snapshot['uploadTotal']);
  }

  void endSession() {
    _archive(_open.values);
    _open = {};
    _sampledAt = null;
  }

  void clearClosed() => _closed.clear();

  void _archive(Iterable<WindowsConnection> entries) {
    for (final entry in entries) {
      _closed.addFirst(entry);
      if (_closed.length > closedLimit) _closed.removeLast();
    }
  }
}

class WindowsConnectionMonitor extends ChangeNotifier {
  WindowsConnectionMonitor(this.runtime, this.groupNames) {
    runtime.addListener(_syncSession);
    _syncSession();
  }

  final RuntimeController runtime;
  final Set<String> Function() groupNames;
  final history = WindowsConnectionHistory();
  final _clock = Stopwatch()..start();
  Timer? _timer;
  MihomoApi? _request;
  int? _pid;
  bool _visible = false;
  bool _disposed = false;
  bool stale = false;
  bool closing = false;

  bool get running => _pid != null;
  int? get count => running && !stale ? history.open.length : null;

  void _syncSession() {
    final pid = runtime.phase == RuntimePhase.running ? runtime.pid : null;
    if (pid == _pid) return;
    _cancelPoll();
    history.endSession();
    stale = false;
    _pid = pid;
    if (pid != null) {
      history.downloaded = 0;
      history.uploaded = 0;
      unawaited(_poll());
    }
    notifyListeners();
  }

  void setVisible(bool visible) {
    if (_visible == visible) return;
    _visible = visible;
    _timer?.cancel();
    unawaited(_poll());
  }

  Future<void> _poll() async {
    if (_disposed || !running || _request != null) return;
    _timer?.cancel();
    final client = runtime.api;
    _request = client;
    try {
      final snapshot = await client.connections();
      if (_request != client) return;
      if (!snapshot.containsKey('connections')) throw const FormatException();
      history.apply(snapshot, at: _clock.elapsed, groupNames: groupNames());
      stale = false;
    } catch (_) {
      if (_request != client) return;
      stale = true;
    } finally {
      if (_request == client) {
        client.close();
        _request = null;
        _timer = Timer(Duration(seconds: _visible ? 1 : 3), _poll);
        notifyListeners();
      }
    }
  }

  Future<void> close({String? id}) async {
    if (!running || closing) return;
    final pid = _pid;
    final client = runtime.api;
    closing = true;
    notifyListeners();
    try {
      if (id == null) {
        await client.closeAllConnections();
      } else {
        await client.closeConnection(id);
      }
    } finally {
      client.close();
      closing = false;
      if (!_disposed) {
        if (_pid == pid) {
          _cancelPoll();
          unawaited(_poll());
        }
        notifyListeners();
      }
    }
  }

  void clearClosed() {
    history.clearClosed();
    notifyListeners();
  }

  void _cancelPoll() {
    _timer?.cancel();
    _request?.close();
    _request = null;
  }

  @override
  void dispose() {
    _disposed = true;
    runtime.removeListener(_syncSession);
    _cancelPoll();
    super.dispose();
  }
}
