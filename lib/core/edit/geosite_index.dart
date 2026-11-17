/// `assets/geo/geosite_index.json` 的读取层。
///
/// 索引由 `tool/build_geosite_index.dart` 从 `assets/geo/geosite.dat` 里扫出来
/// 再提交进仓库：运行期不必解析 protobuf，也能给每个 code 挂中文名。
library;

import 'dart:convert';

import 'package:flutter/services.dart';

/// 索引里的一个 geosite 分类。
class GeositeEntry {
  const GeositeEntry({required this.code, required this.domains});

  /// geosite.dat 里的名字，例如 `microsoft`、`category-ads-all`。
  final String code;

  /// 这个分类下有多少条域名。
  final int domains;

  @override
  String toString() => 'GeositeEntry($code, $domains)';
}

/// 解析索引 JSON。纯函数，方便单测。
///
/// 结构：`{version, generatedFrom, sha256, bytes, names: [{code, domains}]}`。
List<GeositeEntry> parseGeositeIndex(String source) {
  final decoded = jsonDecode(source);
  if (decoded is! Map) return const [];
  final names = decoded['names'];
  if (names is! List) return const [];
  final entries = <GeositeEntry>[];
  for (final item in names) {
    if (item is! Map) continue;
    final code = item['code'];
    if (code is! String || code.isEmpty) continue;
    final domains = item['domains'];
    entries.add(
      GeositeEntry(
        code: code.trim().toLowerCase(),
        domains: domains is int ? domains : 0,
      ),
    );
  }
  return List<GeositeEntry>.unmodifiable(entries);
}

/// 从 assets 读索引。失败时返回空表，调用方按空表降级即可。
Future<List<GeositeEntry>> loadGeositeIndex() async {
  try {
    final source = await rootBundle.loadString('assets/geo/geosite_index.json');
    return parseGeositeIndex(source);
  } on Exception {
    return const [];
  }
}

/// geosite code → 中文名。
///
/// 只收「人点得出名字」的那批；没收录的 code 原样显示（例如 `category-ads-ir`）。
const Map<String, String> kGeositeLabels = {
  // 厂商
  'apple': '苹果 Apple',
  'apple-cn': '苹果 Apple（中国）',
  'apple-dev': '苹果 Apple 开发者',
  'microsoft': '微软 Microsoft',
  'google': '谷歌 Google',
  'google-cn': '谷歌 Google（中国）',
  'amazon': '亚马逊 Amazon',
  'adobe': '奥多比 Adobe',
  'onedrive': '微软 OneDrive',
  'bing': '微软 Bing',
  'github': 'GitHub',
  'cloudflare': 'Cloudflare',
  'akamai': 'Akamai',
  'paypal': 'PayPal',
  'xiaomi': '小米 Xiaomi',
  'huawei': '华为 Huawei',
  'tencent': '腾讯 Tencent',
  'jd': '京东 JD',
  'pinduoduo': '拼多多',
  'baidu': '百度 Baidu',
  // AI
  'openai': 'OpenAI',
  'anthropic': 'Anthropic（Claude）',
  'perplexity': 'Perplexity',
  'cursor': 'Cursor',
  'huggingface': 'Hugging Face',
  'midjourney': 'Midjourney',
  'category-ai-!cn': 'AI 站点（境外）',
  // 流媒体与音乐
  'netflix': 'Netflix',
  'disney': 'Disney+',
  'youtube': 'YouTube',
  'spotify': 'Spotify',
  'tiktok': 'TikTok',
  'bilibili': '哔哩哔哩',
  'bilibili2': '哔哩哔哩（备用）',
  'douyin': '抖音',
  'netease': '网易云音乐',
  'iqiyi': '爱奇艺',
  'youku': '优酷',
  // 社交
  'telegram': 'Telegram',
  'twitter': 'Twitter / X',
  'facebook': 'Facebook',
  'instagram': 'Instagram',
  'whatsapp': 'WhatsApp',
  'line': 'LINE',
  'discord': 'Discord',
  // 游戏
  'steam': 'Steam',
  'epicgames': 'Epic Games',
  'xbox': 'Xbox',
  'playstation': 'PlayStation',
  'nintendo': '任天堂 Nintendo',
  // 分类合集
  'category-ads': '广告与统计',
  'category-ads-all': '广告拦截（全量）',
  'category-ads-and-telemetry': '广告与遥测',
  'category-media': '流媒体合集',
  'category-games': '游戏平台合集',
  'category-acg': '二次元合集',
  'category-social-media-!cn': '境外社交合集',
};

/// 取中文名；没收录就返回原 code。
String geositeLabelOf(String code) {
  final key = code.trim().toLowerCase();
  return kGeositeLabels[key] ?? key;
}
