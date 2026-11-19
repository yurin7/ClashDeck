import 'dart:async';
import 'dart:io';

/// 一次 TCP 连接探测的结果。
///
/// 只记录建连耗时，不区分 IPv4 / IPv6：`Socket.connect` 会按目标地址走，
/// 解析失败、拒绝连接、超时都属于失败，不产生 [TcpDelayResult]。
class TcpDelayResult {
  const TcpDelayResult(this.milliseconds);

  /// 从发起连接到建立完成的毫秒数。
  final int milliseconds;
}

/// 建立 TCP 连接的注入点；测试用它替代真实网络。
typedef TcpConnector = Future<Socket> Function(
  String host,
  int port, {
  Duration? timeout,
});

Future<Socket> _defaultConnector(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 4),
}) => Socket.connect(host, port, timeout: timeout);

/// 内核没运行时也能测的近似延迟：探测 `host:port` 的 TCP 建连耗时。
///
/// - 不启动 VPN、不经过任何节点，只代表「本机到这个地址能否连通、连多快」；
/// - 默认 4 秒超时，`host` 为空或端口不合法时直接返回 `null`；
/// - 连接成功后立刻 `destroy()`，不保留连接；
/// - 解析失败、拒绝连接、超时、取消都返回 `null`（UI 显示「超时」）。
Future<TcpDelayResult?> probeTcpDelay(
  String host,
  int port, {
  Duration timeout = const Duration(seconds: 4),
  TcpConnector? connector,
  bool Function()? isCancelled,
}) async {
  final target = host.trim();
  if (target.isEmpty || port <= 0 || port > 65535) return null;
  if (isCancelled?.call() ?? false) return null;

  final connect = connector ?? _defaultConnector;
  final watch = Stopwatch()..start();
  Socket? socket;
  try {
    socket = await connect(target, port, timeout: timeout);
    watch.stop();
    return TcpDelayResult(watch.elapsedMilliseconds);
  } catch (_) {
    return null;
  } finally {
    // 成功失败都不保留连接：失败时 socket 为 null，成功时立即断开。
    socket?.destroy();
  }
}
