// 生成 GEOSITE 名称索引：`dart run tool/build_geosite_index.dart`
//
// 为什么要生成索引而不是运行期解析：`assets/geo/geosite.dat` 是 v2ray 的
// protobuf 数据（4 MB+），App 里再塞一个 protobuf 解析器只为列出名字不划算；
// 而这份索引要带中文名、要能随版本审阅，所以构建期扫一次、把 JSON 提交进仓库，
// 运行期只读 JSON（离线、快）。升级 `geosite.dat` 后重跑本脚本即可。
//
// 校验模式：`dart run tool/build_geosite_index.dart --check`
// 用当前 `geosite.dat` 的 sha256 与索引里记录的值比对，不一致就 exit 1
// （CI 里跑，防止换了数据却忘记重新生成索引）。
//
// 输出：`assets/geo/geosite_index.json`
//   {"version":1,"generatedFrom":"geosite.dat","sha256":"…","bytes":4356378,
//    "names":[{"code":"apple","domains":29}, …]}
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

const String _sourcePath = 'assets/geo/geosite.dat';
const String _indexPath = 'assets/geo/geosite_index.json';

/// 自检：这几个 code 一定存在且带域名，否则说明解析写错了。
const List<String> _mustHave = ['microsoft', 'apple', 'openai'];
const int _minEntries = 900;

void main(List<String> args) {
  final source = File(_sourcePath);
  if (!source.existsSync()) {
    stderr.writeln('找不到 ${source.path}');
    exitCode = 1;
    return;
  }

  final bytes = source.readAsBytesSync();
  final digest = sha256.convert(bytes).toString();

  if (args.contains('--check')) {
    _check(bytes.length, digest);
    return;
  }

  final names = _readGeositeNames(bytes)
    ..sort((a, b) => a.code.compareTo(b.code));
  if (!_assertSane(names)) {
    exitCode = 1;
    return;
  }

  final out = File(_indexPath);
  out.writeAsStringSync(
    '${const JsonEncoder.withIndent('  ').convert({
      'version': 1,
      'generatedFrom': 'geosite.dat',
      'sha256': digest,
      'bytes': bytes.length,
      'names': [
        for (final entry in names) {'code': entry.code, 'domains': entry.domains},
      ],
    })}\n',
  );
  stdout.writeln('写入 ${out.path}：${names.length} 项，sha256=$digest');
}

void _check(int bytes, String digest) {
  final index = File(_indexPath);
  if (!index.existsSync()) {
    stderr.writeln(
      '找不到 ${index.path}，先跑 `dart run tool/build_geosite_index.dart`',
    );
    exitCode = 1;
    return;
  }
  final json = jsonDecode(index.readAsStringSync()) as Map<String, Object?>;
  final recorded = json['sha256'];
  final recordedBytes = json['bytes'];
  if (recorded != digest || recordedBytes != bytes) {
    stderr.writeln(
      '${_indexPath} 与 ${_sourcePath} 不同版本：\n'
      '  索引 sha256=$recorded bytes=$recordedBytes\n'
      '  数据 sha256=$digest bytes=$bytes\n'
      '请重新运行 `dart run tool/build_geosite_index.dart`。',
    );
    exitCode = 1;
    return;
  }
  stdout.writeln('索引与数据一致（$digest）。');
}

bool _assertSane(List<_GeositeName> names) {
  final problems = <String>[];
  if (names.length < _minEntries) {
    problems.add('只解析出 ${names.length} 项，少于 $_minEntries');
  }
  for (final code in _mustHave) {
    final hit = names.where((entry) => entry.code == code).toList();
    if (hit.isEmpty) {
      problems.add('缺少 $code');
    } else if (hit.first.domains <= 0) {
      problems.add('$code 没有解析出域名');
    }
  }
  if (problems.isEmpty) return true;
  stderr.writeln('geosite.dat 解析结果不合理，已中止：\n  - ${problems.join('\n  - ')}');
  return false;
}

class _GeositeName {
  _GeositeName(this.code, this.domains);

  final String code;
  final int domains;
}

/// 扫 `GeoSiteList{ repeated GeoSite entry = 1 }`。
///
/// `GeoSite{ string country_code = 1; repeated Domain domain = 2; }`，
/// 只关心 code 和 domain 条数，其它字段按 protobuf 规则跳过。
List<_GeositeName> _readGeositeNames(Uint8List bytes) {
  final result = <_GeositeName>[];
  for (final field in _fields(bytes)) {
    if (field.number != 1 || field.bytes == null) continue;
    String? code;
    var domains = 0;
    for (final inner in _fields(field.bytes!)) {
      switch (inner.number) {
        case 1:
          // geosite.dat 里是大写（APPLE/MICROSOFT），统一小写方便写进 YAML。
          code = utf8
              .decode(inner.bytes ?? const [], allowMalformed: true)
              .toLowerCase();
        case 2:
          domains++;
      }
    }
    if (code != null && code.isNotEmpty)
      result.add(_GeositeName(code, domains));
  }
  return result;
}

class _Field {
  _Field(this.number, this.bytes);

  final int number;
  final Uint8List? bytes;
}

/// 最小 protobuf 扫描：只处理 length-delimited 字段，其余按 wire type 跳过。
Iterable<_Field> _fields(Uint8List bytes) sync* {
  var i = 0;
  while (i < bytes.length) {
    final key = _varint(bytes, i);
    if (key == null) return;
    i = key.next;
    final number = key.value >> 3;
    final wire = key.value & 7;
    switch (wire) {
      case 0: // varint
        final skipped = _varint(bytes, i);
        if (skipped == null) return;
        i = skipped.next;
        yield _Field(number, null);
      case 1: // 64-bit
        i += 8;
      case 5: // 32-bit
        i += 4;
      case 2: // length-delimited
        final length = _varint(bytes, i);
        if (length == null) return;
        i = length.next;
        if (i + length.value > bytes.length) return;
        yield _Field(number, Uint8List.sublistView(bytes, i, i + length.value));
        i += length.value;
      default:
        return;
    }
  }
}

class _Varint {
  _Varint(this.value, this.next);

  final int value;
  final int next;
}

_Varint? _varint(Uint8List bytes, int start) {
  var result = 0;
  var shift = 0;
  var i = start;
  while (i < bytes.length) {
    final byte = bytes[i++];
    result |= (byte & 0x7f) << shift;
    if (byte < 0x80) return _Varint(result, i);
    shift += 7;
    if (shift > 63) return null;
  }
  return null;
}
