import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';

/// Windows 桌面端随应用启动和关闭的本地代理内核。
class WindowsKernel {
  static const _channel = MethodChannel('dev.clashdeck/windows-kernel');
  final _logs = ListQueue<String>();
  Future<Directory>? _workDir;
  Process? _process;
  Future<void> Function()? _closeTun;
  Future<void>? _stopping;
  int _operation = 0;

  static Future<bool> isElevated() async =>
      await _channel.invokeMethod<bool>('isElevated') ?? false;

  static Future<bool> relaunchElevated() async =>
      await _channel.invokeMethod<bool>('relaunchElevated') ?? false;

  Future<Directory> get workDir =>
      _workDir ??= Directory.systemTemp.createTemp('clashdeck-windows-');

  List<String> logs(int limit) => _logs
      .skip((_logs.length - limit).clamp(0, _logs.length))
      .toList(growable: false);

  void clearLogs() => _logs.clear();

  static Future<int> controllerPort({required int excluding}) async {
    final socket = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    try {
      if (socket.port != excluding) return socket.port;
      final alternative = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        0,
      );
      try {
        return alternative.port;
      } finally {
        await alternative.close();
      }
    } finally {
      await socket.close();
    }
  }

  Future<int> start({
    required String yaml,
    required int proxyPort,
    required Future<bool> Function() ready,
    required void Function(int) onExit,
    Future<void> Function()? closeTun,
  }) async {
    if (_process != null) throw StateError('内核进程仍在运行');
    final operation = ++_operation;
    final executable = File.fromUri(
      File(Platform.resolvedExecutable).parent.uri.resolve('mihomo.exe'),
    );
    if (!await executable.exists()) {
      throw StateError('应用目录缺少 mihomo.exe');
    }
    try {
      final tcp = await ServerSocket.bind(
        InternetAddress.loopbackIPv4,
        proxyPort,
      );
      try {
        final udp = await RawDatagramSocket.bind(
          InternetAddress.loopbackIPv4,
          proxyPort,
          reuseAddress: false,
        );
        udp.close();
      } finally {
        await tcp.close();
      }
    } on SocketException {
      throw StateError('本地代理端口 $proxyPort 已被占用或被系统保留');
    }
    clearLogs();
    final dir = await workDir;
    final config = File.fromUri(dir.uri.resolve('runtime.yaml'));
    await config.writeAsString(yaml, flush: true);
    if (operation != _operation) throw StateError('启动已取消');
    final process = await Process.start(executable.path, [
      '-d',
      dir.path,
      '-f',
      config.path,
    ], workingDirectory: dir.path);
    if (operation != _operation) {
      process.kill();
      await process.exitCode;
      throw StateError('启动已取消');
    }
    _process = process;
    _closeTun = closeTun;
    _readLogs(process.stdout);
    _readLogs(process.stderr);
    unawaited(
      process.exitCode.then((code) {
        if (_process != process) return;
        _process = null;
        _closeTun = null;
        if (operation == _operation) onExit(code);
      }),
    );
    try {
      await _channel.invokeMethod<void>('track', process.pid);
      final deadline = DateTime.now().add(const Duration(seconds: 12));
      while (DateTime.now().isBefore(deadline)) {
        if (operation != _operation) throw StateError('启动已取消');
        if (_process != process) {
          throw StateError(_logs.isEmpty ? 'mihomo 已退出' : _logs.last);
        }
        final listening = await ready();
        final listenerError = _logs
            .where(
              (line) =>
                  line.contains('Start Mixed(http+socks) server error') ||
                  (closeTun != null &&
                      line.contains('Start TUN listening error')),
            )
            .lastOrNull;
        if (listenerError != null) throw StateError(listenerError);
        if (listening && _process == process && operation == _operation) {
          return process.pid;
        }
        await Future<void>.delayed(const Duration(milliseconds: 150));
      }
      throw StateError(closeTun == null ? '等待 mihomo 控制接口超时' : '等待 TUN 网卡就绪超时');
    } catch (_) {
      if (operation == _operation) await stop();
      rethrow;
    }
  }

  void _readLogs(Stream<List<int>> output) {
    output
        .transform(const Utf8Decoder(allowMalformed: true))
        .transform(const LineSplitter())
        .listen((line) {
          if (_logs.length >= 300) _logs.removeFirst();
          _logs.addLast(line);
        }, onError: (Object _) {});
  }

  Future<void> stop() {
    _operation++;
    return _stopping ??= _stopProcess().whenComplete(() {
      _stopping = null;
    });
  }

  Future<void> _stopProcess() async {
    final process = _process;
    if (process == null) return;
    try {
      // 给内核机会撤销 TUN 路由和 DNS 设置，再结束子进程。
      await _closeTun?.call();
    } catch (_) {
      // 控制接口可能已经退出，仍需回收子进程。
    }
    process.kill();
    await process.exitCode.timeout(const Duration(seconds: 4));
    if (_process == process) _process = null;
  }

  Future<void> dispose() async {
    await stop();
    final dir = await _workDir;
    _workDir = null;
    if (dir != null) {
      try {
        await dir.delete(recursive: true);
      } on FileSystemException {
        // 文件可能短暂被防病毒扫描占用。
      }
    }
  }
}
