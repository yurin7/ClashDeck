import 'dart:async';
import 'dart:io';

import 'package:clashdeck/runtime/tcp_delay_probe.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeSocket extends Fake implements Socket {
  bool destroyed = false;

  @override
  void destroy() {
    destroyed = true;
  }
}

void main() {
  test('连通时返回毫秒数并在结束后 destroy socket', () async {
    final socket = _FakeSocket();
    final result = await probeTcpDelay(
      'example.com',
      443,
      connector: (host, port, {timeout = Duration.zero}) async => socket,
    );
    expect(result, isNotNull);
    expect(result!.milliseconds, greaterThanOrEqualTo(0));
    expect(socket.destroyed, isTrue);
  });

  test('连接超时返回 null', () async {
    final result = await probeTcpDelay(
      'example.com',
      443,
      connector: (host, port, {timeout = Duration.zero}) async =>
          throw TimeoutException('timeout'),
    );
    expect(result, isNull);
  });

  test('连接被拒绝返回 null', () async {
    final result = await probeTcpDelay(
      '127.0.0.1',
      1,
      connector: (host, port, {timeout = Duration.zero}) async =>
          throw const SocketException('connection refused'),
    );
    expect(result, isNull);
  });

  test('地址为空、端口非法或已取消时直接返回 null', () async {
    var called = false;
    Future<Socket> connector(String host, int port, {Duration? timeout}) {
      called = true;
      return Future.value(_FakeSocket());
    }

    expect(await probeTcpDelay('', 443, connector: connector), isNull);
    expect(await probeTcpDelay('example.com', 0, connector: connector), isNull);
    expect(
      await probeTcpDelay('example.com', 70000, connector: connector),
      isNull,
    );
    expect(
      await probeTcpDelay(
        'example.com',
        443,
        connector: connector,
        isCancelled: () => true,
      ),
      isNull,
    );
    expect(called, isFalse);
  });
}
