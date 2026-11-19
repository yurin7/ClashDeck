import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:clashdeck/runtime/speed_test.dart';

class _ChunkedResponse extends Stream<List<int>> implements HttpClientResponse {
  _ChunkedResponse(this.statusCode, this._chunks);

  @override
  final int statusCode;
  final List<List<int>> _chunks;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int> event)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) {
    final source = Stream<List<int>>.fromIterable(_chunks);
    return source.listen(
      onData,
      onError: onError,
      onDone: onDone,
      cancelOnError: cancelOnError,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeRequest implements HttpClientRequest {
  _FakeRequest(this.client, this.url);

  final _FakeHttpClient client;
  final Uri url;

  @override
  bool followRedirects = true;

  @override
  Future<HttpClientResponse> close() async =>
      client.response ?? _ChunkedResponse(200, const []);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeHttpClient implements HttpClient {
  _FakeHttpClient({this.response, this.getUrlError});

  final HttpClientResponse? response;
  final Object? getUrlError;

  String? proxy;
  Duration? timeout;
  bool closed = false;

  @override
  Duration? connectionTimeout;

  @override
  bool autoUncompress = true;

  @override
  set findProxy(String Function(Uri uri)? value) {
    proxy = value?.call(Uri.parse('https://example.test/'));
  }

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    final error = getUrlError;
    if (error != null) throw error;
    return _FakeRequest(this, url);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test('成功：统计字节、代理写进 findProxy、summary 格式正确', () async {
    final client = _FakeHttpClient(
      response: _ChunkedResponse(200, const [
        [1, 2, 3],
        [4, 5, 6],
      ]),
    );
    final downloader = SpeedDownloader(clientFactory: () => client);
    final result = await downloader.download(
      Uri.parse('https://speed.test/file'),
      proxy: '127.0.0.1:7890',
    );
    expect(result.ok, isTrue);
    expect(result.bytes, 6);
    expect(client.proxy, 'PROXY 127.0.0.1:7890');
    expect(client.closed, isTrue);
    expect(result.summary, contains('MB/s'));
  });

  test('HTTP 非 200 记为失败', () async {
    final downloader = SpeedDownloader(
      clientFactory: () =>
          _FakeHttpClient(response: _ChunkedResponse(503, const [])),
    );
    final result = await downloader.download(Uri.parse('https://x.test/'));
    expect(result.ok, isFalse);
    expect(result.failure, 'HTTP 503');
  });

  test('取消：读到下一片前立即中止', () async {
    final token = SpeedTestCancelToken()..cancel();
    final downloader = SpeedDownloader(
      clientFactory: () => _FakeHttpClient(
        response: _ChunkedResponse(200, const [
          [1, 2, 3],
        ]),
      ),
    );
    final result = await downloader.download(
      Uri.parse('https://x.test/'),
      cancelToken: token,
    );
    expect(result.ok, isFalse);
    expect(result.cancelled, isTrue);
    expect(result.failure, '已取消');
  });

  test('超过 maxBytes 时截断并记录上限字节数', () async {
    final downloader = SpeedDownloader(
      clientFactory: () => _FakeHttpClient(
        response: _ChunkedResponse(200, const [
          [1, 2, 3, 4, 5],
          [6, 7, 8, 9, 10],
        ]),
      ),
    );
    final result = await downloader.download(
      Uri.parse('https://x.test/'),
      maxBytes: 7,
    );
    expect(result.ok, isTrue);
    expect(result.bytes, 7);
  });

  test('连接超时', () async {
    final downloader = SpeedDownloader(
      clientFactory: () =>
          _FakeHttpClient(getUrlError: TimeoutException('timeout')),
    );
    final result = await downloader.download(Uri.parse('https://x.test/'));
    expect(result.ok, isFalse);
    expect(result.failure, '连接超时');
  });

  test('自定义地址校验', () {
    const ok = SpeedSourceChoice(SpeedSource.custom, 'https://a.test/b');
    const bad = SpeedSourceChoice(SpeedSource.custom, 'ftp://a');
    expect(ok.url, isNotNull);
    expect(bad.url, isNull);
    expect(
      SpeedSourceChoice.defaultChoice.url.toString(),
      contains('cloudflare'),
    );
  });
}
