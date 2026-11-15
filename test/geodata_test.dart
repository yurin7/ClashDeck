import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/runtime/geodata.dart';

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clashdeck-geodata');
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('缺文件时按文件名写进工作目录', () async {
    final written = await Geodata.ensureFrom(tmp, {
      'geoip.metadb': Uint8List.fromList(List.filled(16, 1)),
      'geosite.dat': Uint8List.fromList(List.filled(8, 2)),
    });

    expect(written, containsAll(['geoip.metadb', 'geosite.dat']));
    final meta = File('${tmp.path}${Platform.pathSeparator}geoip.metadb');
    final site = File('${tmp.path}${Platform.pathSeparator}geosite.dat');
    expect(await meta.length(), 16);
    expect(await site.length(), 8);
    // 临时文件不能残留
    expect(
      tmp.listSync().where((e) => e.path.endsWith('.tmp')),
      isEmpty,
    );
  });

  test('已有非空文件不重写（省掉每次启动几十 MB 的 IO）', () async {
    final meta = File('${tmp.path}${Platform.pathSeparator}geoip.metadb');
    await meta.writeAsBytes([9, 9, 9], flush: true);

    final written = await Geodata.ensureFrom(tmp, {
      'geoip.metadb': Uint8List.fromList(List.filled(16, 1)),
      'geosite.dat': Uint8List.fromList(List.filled(8, 2)),
    });

    expect(written, ['geosite.dat']);
    expect(await meta.readAsBytes(), [9, 9, 9]);
  });

  test('加载失败不抛异常（内核会退回自己下载）', () async {
    final written = await Geodata.ensureFrom(tmp, const {});
    expect(written, isEmpty);
    expect(tmp.existsSync(), isTrue);
  });
}
