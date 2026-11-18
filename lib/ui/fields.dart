import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// 单行输入框的统一视觉高度（含边框）。
///
/// 只用于断言/对齐参考：真正的实现靠 [fieldDecoration] 的固定内边距，
/// 多行输入框（导入粘贴、备注）会自然变高，这是预期的。
const double kFieldHeight = 44;

/// 全 App 统一的输入框装饰。
///
/// 尺寸、圆角、内边距都在这里，别再给单个输入框写 `InputDecoration`，
/// 否则「新建组」「编辑规则」「搜索」几个框的高度会各不相同。
InputDecoration fieldDecoration({
  String? label,
  String? hint,
  String? helper,
  String? error,
  Widget? prefixIcon,
  Widget? suffixIcon,
  bool enabled = true,
  bool alignLabelWithHint = false,
}) {
  return InputDecoration(
    isDense: true,
    labelText: label,
    hintText: hint,
    helperText: helper,
    errorText: error,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    // 前缀/后缀图标别把输入框撑高：默认约束是 48 高，会把带搜索图标的框
    // 顶成「比别的框高一头」。
    prefixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
    suffixIconConstraints: const BoxConstraints(minWidth: 40, minHeight: 20),
    enabled: enabled,
    alignLabelWithHint: alignLabelWithHint,
    contentPadding: const EdgeInsets.symmetric(
      horizontal: Insets.md,
      vertical: 12,
    ),
    border: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radiuses.md),
    ),
    enabledBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radiuses.md),
    ),
    focusedBorder: OutlineInputBorder(
      borderRadius: BorderRadius.circular(Radiuses.md),
    ),
  );
}

/// 单行输入的便捷封装：统一装饰 + 统一字号。
class AppTextField extends StatelessWidget {
  const AppTextField({
    super.key,
    this.controller,
    this.initialValue,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.prefixIcon,
    this.suffixIcon,
    this.style,
    this.keyboardType,
    this.textInputAction,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.autofocus = false,
    this.alignLabelWithHint = false,
    this.onChanged,
    this.onSubmitted,
  });

  final TextEditingController? controller;
  final String? initialValue;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final TextStyle? style;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final bool autofocus;
  final bool alignLabelWithHint;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: minLines,
      maxLines: maxLines,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      style: style ?? const TextStyle(fontSize: 13.5),
      decoration: fieldDecoration(
        label: label,
        hint: hint,
        helper: helper,
        error: error,
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        enabled: enabled,
        alignLabelWithHint: alignLabelWithHint,
      ),
    );
  }
}
