/// 运行配置模板：把实际 TUN fd 换成占位 0，供无 Flutter 的冷启动路径复用。
///
/// 两类场景：
/// 1. Flutter 活着时由 Dart 现算 runtime YAML，同时写一份 `.tpl`；
/// 2. 磁贴/小组件/通知走无 UI 的 `ClashActionActivity` 冷启动时，
///    Kotlin 读 `.tpl` 把占位替换成实际 fd 再 spawn。
library;

final RegExp _fdLine = RegExp(
  r'^(\s*)file-descriptor:\s*-?\d+\s*$',
  multiLine: true,
);

/// 把 `file-descriptor: <n>` 统一换成占位 `0`。
///
/// 只动这一行，其它内容（注释、缩进、锚点）原样保留。
String runtimeTemplateFrom(String yaml) {
  return yaml.replaceAllMapped(_fdLine, (m) => '${m[1]}file-descriptor: 0');
}

/// 用实际 fd 替换模板占位。
String runtimeYamlFromTemplate(String template, int fd) {
  return template.replaceAllMapped(
    _fdLine,
    (m) => '${m[1]}file-descriptor: $fd',
  );
}

/// 模板里是否带着可替换的 `file-descriptor` 行。
bool runtimeTemplateHasPlaceholder(String template) =>
    _fdLine.hasMatch(template);
