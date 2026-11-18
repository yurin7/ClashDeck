import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart';

import '../../core/io/yaml_file.dart';

/// 选文件的动作可以从测试里替换。
typedef YamlFilePicker = Future<PickedYamlFile?> Function();

/// 调系统文件选择器（SAF），只允许 yaml / yml / txt。
///
/// - 用户取消返回 null；
/// - 打不开选择器 / 读不出内容抛 [YamlFileException]（UI 直接 toast）；
/// - 先看文件大小，超过 2MB 不再读进内存。
Future<PickedYamlFile?> pickYamlFileFromDevice() async {
  final PlatformFile? file;
  try {
    file = await FilePicker.pickFile(
      dialogTitle: '选择 YAML / 订阅文件',
      type: FileType.custom,
      allowedExtensions: yamlFileExtensions.toList(),
    );
  } on PlatformException {
    throw const YamlFileException('无法打开系统文件选择器');
  }
  if (file == null) return null;

  try {
    final length = await file.length();
    if (length != null && length > maxYamlFileBytes) {
      throw const YamlFileException('文件超过 2MB，请换一份配置');
    }
  } on YamlFileException {
    rethrow;
  } catch (_) {
    // 平台拿不到大小就继续读，最终由 decodeYamlFile 兜底。
  }

  try {
    final bytes = await file.readAsBytes();
    return PickedYamlFile(name: file.name, bytes: bytes);
  } catch (_) {
    throw const YamlFileException('读取文件失败，请重试');
  }
}
