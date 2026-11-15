import 'package:yaml/yaml.dart';
import 'package:yaml_edit/yaml_edit.dart';

/// 一次"无损"编辑的结果：新的源码文本 + 重新解析的语法树。
///
/// 设计约定（见 docs/ARCHITECTURE.md）：
/// * 配置的唯一真相是**源码文本**；所有编辑都是 `旧文本 -> 新文本` 的纯函数；
/// * 具体写操作交给 [YamlEditor]（yaml_edit），它只替换受影响的 span，
///   因此注释、空行、键顺序、未知字段全部逐字保留；
/// * 编辑后立即重新解析，语法错误在编辑时就能暴露。
class YamlDoc {
  const YamlDoc._(this.text, this.root, this.error);

  final String text;
  final YamlNode? root;
  final YamlException? error;

  factory YamlDoc.parse(String text) {
    try {
      final node = loadYamlNode(text);
      return YamlDoc._(text, node, null);
    } on YamlException catch (e) {
      return YamlDoc._(text, null, e);
    }
  }

  static YamlDoc empty() => YamlDoc.parse('');

  bool get isValid => error == null && root is YamlMap;

  YamlMap? get rootMap => root is YamlMap ? root as YamlMap : null;

  /// 根节点的纯 Dart 视图（保持键顺序）。
  Map<String, Object?> get plainRoot {
    final m = rootMap;
    if (m == null) return <String, Object?>{};
    return toPlainMap(m);
  }

  YamlNode? nodeAt(List<Object?> path) {
    YamlNode? cur = root;
    for (final seg in path) {
      if (cur == null) return null;
      if (seg is int) {
        if (cur is! YamlList || seg < 0 || seg >= cur.length) return null;
        cur = cur.nodes[seg];
      } else {
        if (cur is! YamlMap) return null;
        cur = cur.nodes[seg];
      }
    }
    return cur;
  }

  Object? plainAt(List<Object?> path) => toPlain(nodeAt(path));

  /// 对文本应用一次 [YamlEditor] 操作，返回新文档。
  ///
  /// [op] 内抛出的任何异常都会被包成 [ConfigEditException]，
  /// 调用方因此可以"失败即无副作用"。
  YamlDoc apply(void Function(YamlEditor editor) op) {
    final editor = YamlEditor(text);
    try {
      op(editor);
    } catch (e) {
      throw ConfigEditException('$e');
    }
    final next = YamlDoc.parse(editor.toString());
    if (next.error != null) {
      throw ConfigEditException('编辑产生了非法 YAML：${next.error!.message}');
    }
    return next;
  }

  @override
  String toString() => text;

  // ---------------------------------------------------------------- 工具函数

  /// 把 YamlMap/YamlList/scalar 转成可再序列化的纯 Dart 结构（保序）。
  static Map<String, Object?> toPlainMap(Map<Object?, Object?> m) {
    final out = <String, Object?>{};
    for (final entry in m.entries) {
      out['${entry.key}'] = toPlain(entry.value);
    }
    return out;
  }

  static Object? toPlain(Object? value) {
    // 注意：YamlMap 同时是 Map（MapMixin），必须先判 YamlScalar/YamlMap，
    // 否则标量节点会把 YamlScalar 对象泄漏到"纯 Dart"结构里。
    if (value is YamlScalar) {
      final v = value.value;
      return v is YamlNode ? toPlain(v) : v;
    }
    if (value is YamlMap) {
      final out = <String, Object?>{};
      for (final entry in value.nodes.entries) {
        out['${toPlain(entry.key)}'] = toPlain(entry.value);
      }
      return out;
    }
    if (value is YamlList) return value.nodes.map(toPlain).toList();
    if (value is Map) return toPlainMap(value);
    if (value is List) return value.map(toPlain).toList();
    return value;
  }

  /// 判断某路径是否存在（区别于"值为 null"）。
  bool has(List<Object?> path) => nodeAt(path) != null;
}

class ConfigEditException implements Exception {
  ConfigEditException(this.message);
  final String message;
  @override
  String toString() => 'ConfigEditException: $message';
}
