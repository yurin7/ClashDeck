import 'dart:convert';

import 'package:clashdeck/core/update/update_check.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:flutter_test/flutter_test.dart';

/// 造一个 `releases/latest` 的 JSON。
String releaseJson({
  required String tag,
  String url = 'https://github.com/yurin7/ClashDeck/releases/tag/v0.2.2',
  String body = '- 新增检查更新\n- 修复若干问题',
  String published = '2026-11-19T00:00:00Z',
}) {
  return jsonEncode({
    'tag_name': tag,
    'html_url': url,
    'body': body,
    'published_at': published,
  });
}

void main() {
  Future<UpdateCheckResult> run(
    String body, {
    String current = '0.2.1',
    Future<String> Function(Uri uri)? thrower,
  }) {
    return checkForUpdate(
      currentVersion: current,
      fetch:
          (uri, {headers = const {}, timeout = const Duration(seconds: 10)}) {
            if (thrower != null) return thrower(uri);
            return Future.value(body);
          },
    );
  }

  test('远端更新 → UpdateAvailable，并带版本/说明/日期', () async {
    final result = await run(releaseJson(tag: 'v0.2.2'));
    expect(result, isA<UpdateAvailable>());
    final info = (result as UpdateAvailable).info;
    expect(info.version, '0.2.2');
    expect(info.url, contains('/releases/tag/v0.2.2'));
    expect(info.notes, contains('检查更新'));
    expect(info.publishedAt, DateTime.utc(2026, 11, 19));
  });

  test('远端相同或更旧 → UpToDate', () async {
    expect(await run(releaseJson(tag: 'v0.2.1')), isA<UpToDate>());
    expect(await run(releaseJson(tag: 'v0.1.9')), isA<UpToDate>());
  });

  test('本机版本带 build 元数据也能比较', () async {
    final result = await run(releaseJson(tag: 'v0.2.2'), current: '0.2.1+2072');
    expect(result, isA<UpdateAvailable>());
  });

  test('403 → 限流文案', () async {
    final result = await run(
      '',
      thrower: (_) async => throw ConfigEditException('拉取失败：HTTP 403'),
    );
    expect(result, isA<UpdateFailed>());
    expect(
      (result as UpdateFailed).failure.kind,
      UpdateFailureKind.rateLimited,
    );
    expect(result.failure.message, 'GitHub 限流，稍后再试');
  });

  test('404 → 还没有发布版本', () async {
    final result = await run(
      '',
      thrower: (_) async => throw ConfigEditException('拉取失败：HTTP 404'),
    );
    expect((result as UpdateFailed).failure.kind, UpdateFailureKind.noRelease);
    expect(result.failure.message, '还没有发布版本');
  });

  test('网络错误 → network', () async {
    final result = await run(
      '',
      thrower: (_) async =>
          throw ConfigEditException('网络错误：Connection refused'),
    );
    expect((result as UpdateFailed).failure.kind, UpdateFailureKind.network);
    expect(result.failure.message, '网络不可用，检查更新失败');
  });

  test('坏 JSON → parse', () async {
    final result = await run('not json');
    expect((result as UpdateFailed).failure.kind, UpdateFailureKind.parse);
  });

  test('缺少 tag_name → parse', () async {
    final result = await run(jsonEncode({'html_url': 'x'}));
    expect((result as UpdateFailed).failure.kind, UpdateFailureKind.parse);
  });

  test('本机版本无法解析 → parse', () async {
    final result = await run(releaseJson(tag: 'v0.2.2'), current: 'dev');
    expect((result as UpdateFailed).failure.kind, UpdateFailureKind.parse);
  });

  test('请求带 ClashDeck/<version> UA', () async {
    late Map<String, String> captured;
    await checkForUpdate(
      currentVersion: '0.2.1',
      fetch:
          (uri, {headers = const {}, timeout = const Duration(seconds: 10)}) {
            captured = Map<String, String>.from(headers);
            return Future.value(releaseJson(tag: 'v0.2.1'));
          },
    );
    expect(captured['User-Agent'], 'ClashDeck/0.2.1');
    expect(captured['Accept'], contains('github'));
  });
}
