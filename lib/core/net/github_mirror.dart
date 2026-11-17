/// GitHub raw 地址的镜像映射。
///
/// `raw.githubusercontent.com` 在国内网络下经常超时或被限速（实测同一仓库里
/// 有的文件能拿到、有的大文件 20s 一个字节都收不到），所以拉规则集要按顺序
/// 试几个镜像；写进 YAML 的 `rule-providers.url` 也必须用能直连的镜像，
/// 否则内核运行时拉 provider 一样会失败。
class GithubMirror {
  const GithubMirror._();

  /// 公共加速站，最后兜底。
  static const String ghProxyBase = 'https://ghproxy.net/';

  /// 把 [url] 展开成「jsdelivr → 原地址 → ghproxy」的候选列表。
  ///
  /// jsdelivr 排第一：实测它稳定，而 raw 在墙内经常 15s 一个字节都收不到，
  /// 把 raw 放前面会让 44 个预设的导入从十几秒变成十几分钟。
  ///
  /// 不是 GitHub raw 地址时原样返回，调用方就只会试一次。
  static List<String> candidates(String url) {
    final parsed = _parseRaw(url);
    if (parsed == null) return [url];
    return [_jsdelivr(parsed), url, '$ghProxyBase$url'];
  }

  /// 写进 YAML 的地址：优先 jsdelivr（内核运行时也要能拉到）。
  ///
  /// 拆不出 owner/repo 时返回原地址。
  static String preferred(String url) {
    final parsed = _parseRaw(url);
    if (parsed == null) return url;
    return _jsdelivr(parsed);
  }

  static String _jsdelivr(_RawParts parts) =>
      'https://cdn.jsdelivr.net/gh/${parts.owner}/${parts.repo}'
      '@${parts.branch}/${parts.path}';

  /// 解析 `https://raw.githubusercontent.com/<owner>/<repo>/<branch>/<path>`。
  static _RawParts? _parseRaw(String url) {
    final uri = Uri.tryParse(url.trim());
    if (uri == null) return null;
    if (uri.host != 'raw.githubusercontent.com') return null;
    final segments = uri.pathSegments;
    if (segments.length < 4) return null;
    return _RawParts(
      owner: segments[0],
      repo: segments[1],
      branch: segments[2],
      path: segments.skip(3).join('/'),
    );
  }
}

class _RawParts {
  const _RawParts({
    required this.owner,
    required this.repo,
    required this.branch,
    required this.path,
  });

  final String owner;
  final String repo;
  final String branch;
  final String path;
}
