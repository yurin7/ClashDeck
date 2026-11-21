import 'dart:async';
import 'dart:convert';

import '../net/fetch_text.dart';
import '../yaml/yaml_doc.dart';
import 'semver.dart';

const String clashDeckProjectUrl = 'https://github.com/yurin7/ClashDeck';

/// 检查更新使用的正式发布信息。
const String latestReleaseUrl =
    'https://api.github.com/repos/yurin7/ClashDeck/releases/latest';

/// 检查失败的分类：界面按类型给不同文案，自动检查时全部静默。
enum UpdateFailureKind { network, rateLimited, noRelease, parse }

class UpdateFailure {
  const UpdateFailure(this.kind, this.message);

  final UpdateFailureKind kind;
  final String message;
}

class UpdateApk {
  const UpdateApk({required this.name, required this.url, required this.size});

  final String name;
  final Uri url;
  final int size;
}

/// 一次成功解析出的版本信息。
class UpdateInfo {
  const UpdateInfo({
    required this.version,
    required this.url,
    required this.notes,
    this.publishedAt,
    this.androidApks = const {},
  });

  /// 规范化的 `major.minor.patch`。
  final String version;

  /// Release 页面地址（去下载用）。
  final String url;

  /// Release 说明（纯文本展示）。
  final String notes;

  final DateTime? publishedAt;

  /// 可直接安装的 APK，按 Android ABI 索引。
  final Map<String, UpdateApk> androidApks;
}

/// 检查结果：有新版本 / 已是最新 / 失败。
sealed class UpdateCheckResult {
  const UpdateCheckResult();
}

class UpdateAvailable extends UpdateCheckResult {
  const UpdateAvailable(this.info);

  final UpdateInfo info;
}

class UpToDate extends UpdateCheckResult {
  const UpToDate(this.info);

  final UpdateInfo info;
}

class UpdateFailed extends UpdateCheckResult {
  const UpdateFailed(this.failure);

  final UpdateFailure failure;
}

/// 拉取一段文本（默认走应用统一的 [fetchText]，测试可注入假实现）。
typedef UpdateFetcher = Future<String> Function(
  Uri uri, {
  Map<String, String> headers,
  Duration timeout,
});

Future<String> _defaultFetcher(
  Uri uri, {
  Map<String, String> headers = const <String, String>{},
  Duration timeout = const Duration(seconds: 10),
}) {
  return fetchText(uri.toString(), headers: headers, timeout: timeout);
}

/// 查询 GitHub 最新 Release，并与本机版本比较。
///
/// - 只读 `releases/latest`（正式仓库的 Latest 就是最新正式版）；
/// - 10s 超时；UA 带 `ClashDeck/<version>`（GitHub 对无 UA 的请求会 403）；
/// - 403/429 记为「限流」，文案是给人看的「GitHub 限流，稍后再试」。
Future<UpdateCheckResult> checkForUpdate({
  required String currentVersion,
  UpdateFetcher? fetch,
  Duration timeout = const Duration(seconds: 10),
}) async {
  final local = SemVer.tryParse(currentVersion);
  if (local == null) {
    return const UpdateFailed(
      UpdateFailure(UpdateFailureKind.parse, '当前版本号无法解析'),
    );
  }

  final String body;
  try {
    body = await (fetch ?? _defaultFetcher)(
      Uri.parse(latestReleaseUrl),
      headers: <String, String>{
        'Accept': 'application/vnd.github+json',
        'User-Agent': 'ClashDeck/$currentVersion',
      },
      timeout: timeout,
    );
  } on ConfigEditException catch (e) {
    return UpdateFailed(_classifyFetchError(e.message));
  } catch (e) {
    return UpdateFailed(UpdateFailure(UpdateFailureKind.network, '检查更新失败：$e'));
  }

  final Object? decoded;
  try {
    decoded = jsonDecode(body);
  } on FormatException {
    return const UpdateFailed(
      UpdateFailure(UpdateFailureKind.parse, 'GitHub 返回的内容无法解析'),
    );
  }
  if (decoded is! Map) {
    return const UpdateFailed(
      UpdateFailure(UpdateFailureKind.parse, 'GitHub 返回的内容无法解析'),
    );
  }

  final data = decoded.cast<String, Object?>();
  final tag = '${data['tag_name'] ?? ''}'.trim();
  final remote = SemVer.tryParse(tag);
  if (remote == null) {
    return const UpdateFailed(
      UpdateFailure(UpdateFailureKind.parse, '最新版本号无法解析'),
    );
  }

  final info = UpdateInfo(
    version: remote.display,
    url: '${data['html_url'] ?? ''}'.trim(),
    notes: '${data['body'] ?? ''}'.trim(),
    publishedAt: DateTime.tryParse('${data['published_at'] ?? ''}'),
    androidApks: _androidApks(data['assets'], tag, remote.display),
  );

  return remote > local ? UpdateAvailable(info) : UpToDate(info);
}

Map<String, UpdateApk> _androidApks(
  Object? assets,
  String tag,
  String version,
) {
  if (assets is! List) return const {};
  final apks = <String, UpdateApk>{};
  for (final abi in ['arm64-v8a', 'x86_64']) {
    final name = 'ClashDeck-$version-$abi.apk';
    final url = '$clashDeckProjectUrl/releases/download/$tag/$name';
    for (final asset in assets) {
      if (asset is! Map ||
          asset['name'] != name ||
          asset['browser_download_url'] != url) {
        continue;
      }
      final size = asset['size'];
      if (size is! int || size <= 0) continue;
      apks[abi] = UpdateApk(name: name, url: Uri.parse(url), size: size);
      break;
    }
  }
  return apks;
}

UpdateFailure _classifyFetchError(String message) {
  if (message.contains('HTTP 403') || message.contains('HTTP 429')) {
    return const UpdateFailure(UpdateFailureKind.rateLimited, 'GitHub 限流，稍后再试');
  }
  if (message.contains('HTTP 404')) {
    return const UpdateFailure(UpdateFailureKind.noRelease, '还没有发布版本');
  }
  if (message.contains('超时') ||
      message.toLowerCase().contains('timeout') ||
      message.contains('网络') ||
      message.contains('Socket')) {
    return UpdateFailure(UpdateFailureKind.network, '网络不可用，检查更新失败');
  }
  return UpdateFailure(UpdateFailureKind.network, message);
}
