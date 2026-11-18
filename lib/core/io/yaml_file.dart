import 'dart:convert';
import 'dart:typed_data';

/// YAML 配置文件导入的上限（2MB）。超过后不解析，直接给出可读提示。
const int maxYamlFileBytes = 2 * 1024 * 1024;

const Set<String> yamlFileExtensions = <String>{'yaml', 'yml', 'txt'};

/// 待导入的文件：原始文件名（含扩展名）+ 字节内容。
class PickedYamlFile {
  const PickedYamlFile({required this.name, required this.bytes});

  final String name;
  final Uint8List bytes;
}

/// 文件导入阶段的可读错误；UI 直接 toast `message`。
class YamlFileException implements Exception {
  const YamlFileException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// 扩展名是否允许（忽略大小写）。
bool hasYamlFileExtension(String fileName) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  if (dot <= 0 || dot == base.length - 1) return false;
  return yamlFileExtensions.contains(base.substring(dot + 1).toLowerCase());
}

/// 用文件名做配置名（去掉扩展名与目录）；空名字回落到「导入的配置」。
String configNameFromFileName(String fileName) {
  final base = fileName.split(RegExp(r'[\\/]')).last;
  final dot = base.lastIndexOf('.');
  // .yaml 这类隐藏文件名没有主干，回落到默认名。
  final name = dot > 0 ? base.substring(0, dot) : (dot == 0 ? '' : base);
  final trimmed = name.trim();
  return trimmed.isEmpty ? '导入的配置' : trimmed;
}

/// 校验并解码文件内容。
///
/// 依次区分「扩展名不支持 / 文件过大 / 不是 UTF-8 / 文件为空」，
/// 解析失败留给调用方的 YAML 校验（[YamlFileException] 只管字节层）。
String decodeYamlFile(PickedYamlFile file) {
  if (!hasYamlFileExtension(file.name)) {
    throw const YamlFileException('只支持 .yaml / .yml / .txt 文件');
  }
  if (file.bytes.length > maxYamlFileBytes) {
    throw const YamlFileException('文件超过 2MB，请换一份配置');
  }

  String text;
  try {
    text = utf8.decode(file.bytes, allowMalformed: false);
  } on FormatException {
    throw const YamlFileException('文件不是 UTF-8 文本');
  }

  if (text.startsWith('\uFEFF')) text = text.substring(1);
  if (text.trim().isEmpty) {
    throw const YamlFileException('文件是空的');
  }
  return text;
}
