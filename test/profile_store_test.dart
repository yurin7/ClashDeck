import 'dart:io';

import 'package:clashdeck/data/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// `ProfileStore.list` 的排序契约：mtime 倒序，同一毫秒时按文件名兜底。
/// 之前只按 mtime 排，CI（Linux）上几份配置常落在同一毫秒，列表顺序会
/// 随文件系统枚举顺序漂移，UI 回归测试随之翻车。
void main() {
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('clashdeck_store_test');
  });

  tearDown(() {
    tmp.deleteSync(recursive: true);
  });

  Future<List<String>> listedNames() async {
    final store = ProfileStore(tmp);
    return [for (final item in await store.list()) item.fileName];
  }

  test('mtime 相同时按文件名排序，顺序确定', () async {
    const names = ['正常.yaml', '坏配置.yaml', '订阅.yaml'];
    for (final name in names) {
      File('${tmp.path}${Platform.pathSeparator}$name')
          .writeAsStringSync('proxies: []\n');
    }
    final sameInstant = DateTime(2026, 1, 1, 12);
    for (final name in names) {
      File('${tmp.path}${Platform.pathSeparator}$name')
          .setLastModifiedSync(sameInstant);
    }

    // 按 UTF-16 码元：坏配置(574F) < 正常(6B63) < 订阅(8BA2)。
    expect(await listedNames(), ['坏配置.yaml', '正常.yaml', '订阅.yaml']);
  });

  test('修改时间不同时新的排前面', () async {
    const names = ['正常.yaml', '订阅.yaml'];
    for (final name in names) {
      File('${tmp.path}${Platform.pathSeparator}$name')
          .writeAsStringSync('proxies: []\n');
    }
    final base = DateTime(2026, 1, 1, 12);
    File('${tmp.path}${Platform.pathSeparator}正常.yaml')
        .setLastModifiedSync(base);
    File('${tmp.path}${Platform.pathSeparator}订阅.yaml')
        .setLastModifiedSync(base.add(const Duration(minutes: 1)));

    expect(await listedNames(), ['订阅.yaml', '正常.yaml']);
  });

  test('只列 .yaml，且忽略子目录', () async {
    File('${tmp.path}${Platform.pathSeparator}a.yaml')
        .writeAsStringSync('proxies: []\n');
    File('${tmp.path}${Platform.pathSeparator}a.yaml.meta.json')
        .writeAsStringSync('{}');
    Directory('${tmp.path}${Platform.pathSeparator}sub').createSync();

    expect(await listedNames(), ['a.yaml']);
  });

  test('重名导入自动加 -2，返回的展示名同步带上后缀', () async {
    final store = ProfileStore(tmp);
    const yaml = 'proxies: []\n';
    final first = await store.create('demo', yaml);
    final second = await store.create('demo', yaml);

    expect(first.fileName, 'demo.yaml');
    expect(second.fileName, 'demo-2.yaml');
    expect(second.name, 'demo-2');
    expect(await listedNames(), ['demo-2.yaml', 'demo.yaml']);
  });
}
