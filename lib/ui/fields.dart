import 'package:flutter/services.dart';
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
    // 长提示/长报错最多两行，超出省略，避免把弹窗按钮挤出屏幕。
    helperMaxLines: 2,
    errorMaxLines: 2,
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
///
/// 业务代码不应该再直接写 `TextField`（自检里有规则拦）。个别需要自定义
/// 装饰的地方把 [decoration] 传进来，会与统一装饰合并；边框/圆角仍以统一
/// 装修为准，避免又出现「有的框圆角 4、有的 14」。
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
    this.expands = false,
    this.enabled = true,
    this.autofocus = false,
    this.alignLabelWithHint = false,
    this.obscureText = false,
    this.readOnly = false,
    this.maxLength,
    this.focusNode,
    this.decoration,
    this.textAlign = TextAlign.start,
    this.textAlignVertical,
    this.inputFormatters,
    this.autocorrect = true,
    this.enableSuggestions = true,
    this.onChanged,
    this.onSubmitted,
    this.onTap,
    this.onEditingComplete,
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
  final bool expands;
  final bool enabled;
  final bool autofocus;
  final bool alignLabelWithHint;
  final bool obscureText;
  final bool readOnly;
  final int? maxLength;
  final FocusNode? focusNode;

  /// 额外的装饰（如计数、清空按钮）。边框和字号仍由统一装修决定。
  final InputDecoration? decoration;
  final TextAlign textAlign;
  final TextAlignVertical? textAlignVertical;
  final List<TextInputFormatter>? inputFormatters;
  final bool autocorrect;
  final bool enableSuggestions;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final VoidCallback? onTap;
  final VoidCallback? onEditingComplete;

  @override
  Widget build(BuildContext context) {
    final base = fieldDecoration(
      label: label,
      hint: hint,
      helper: helper,
      error: error,
      prefixIcon: prefixIcon,
      suffixIcon: suffixIcon,
      enabled: enabled,
      alignLabelWithHint: alignLabelWithHint,
    );
    final extra = decoration;
    final merged = extra == null
        ? base
        : base.copyWith(
            labelText: extra.labelText ?? base.labelText,
            hintText: extra.hintText ?? base.hintText,
            helperText: extra.helperText ?? base.helperText,
            errorText: extra.errorText ?? base.errorText,
            counterText: extra.counterText,
            counter: extra.counter,
            prefixIcon: extra.prefixIcon ?? base.prefixIcon,
            suffixIcon: extra.suffixIcon ?? base.suffixIcon,
            suffixText: extra.suffixText,
            hintStyle: extra.hintStyle,
            helperStyle: extra.helperStyle,
            errorStyle: extra.errorStyle,
            labelStyle: extra.labelStyle,
            floatingLabelBehavior: extra.floatingLabelBehavior,
            semanticCounterText: extra.semanticCounterText,
          );

    return TextField(
      controller: controller,
      focusNode: focusNode,
      readOnly: readOnly,
      obscureText: obscureText,
      maxLength: maxLength,
      autofocus: autofocus,
      enabled: enabled,
      keyboardType: keyboardType,
      textInputAction: textInputAction,
      minLines: expands ? null : minLines,
      maxLines: expands ? null : maxLines,
      expands: expands,
      textAlign: textAlign,
      textAlignVertical: textAlignVertical,
      inputFormatters: inputFormatters,
      autocorrect: autocorrect,
      enableSuggestions: enableSuggestions,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onTap: onTap,
      onEditingComplete: onEditingComplete,
      style: style ?? const TextStyle(fontSize: 13.5),
      decoration: merged,
    );
  }
}

/// 多行文本域：所有「粘贴多行链接 / 大段文本」的地方都用它。
///
/// 宽度撑满可用宽，高度约 `0.8 × 宽度`（上限 320），自动换行，
/// 内容超出时在框内滚动；不再用 `minLines/maxLines` 手写高度，
/// 否则不同弹窗里的文本域高矮不一。
class AppTextArea extends StatelessWidget {
  const AppTextArea({
    super.key,
    this.controller,
    this.label,
    this.hint,
    this.helper,
    this.error,
    this.autofocus = false,
    this.enabled = true,
    this.monospace = false,
    this.minHeight = 110,
    this.maxHeight = 320,
    this.onChanged,
  });

  final TextEditingController? controller;
  final String? label;
  final String? hint;
  final String? helper;
  final String? error;
  final bool autofocus;
  final bool enabled;

  /// 等宽字体：YAML、多行链接、base64 之类。
  final bool monospace;
  final double minHeight;
  final double maxHeight;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final height = (width * 0.8).clamp(minHeight, maxHeight).toDouble();
        return SizedBox(
          height: height,
          child: AppTextField(
            controller: controller,
            label: label,
            hint: hint,
            helper: helper,
            error: error,
            enabled: enabled,
            autofocus: autofocus,
            keyboardType: TextInputType.multiline,
            textInputAction: TextInputAction.newline,
            minLines: null,
            maxLines: null,
            expands: true,
            textAlignVertical: TextAlignVertical.top,
            alignLabelWithHint: true,
            style: monospace
                ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                : null,
            onChanged: onChanged,
          ),
        );
      },
    );
  }
}

/// 搜索输入框：统一带放大镜图标与清空按钮。
class AppSearchField extends StatelessWidget {
  const AppSearchField({
    super.key,
    required this.controller,
    this.hint = '搜索',
    this.onChanged,
    this.autofocus = false,
  });

  final TextEditingController controller;
  final String hint;
  final ValueChanged<String>? onChanged;
  final bool autofocus;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ValueListenableBuilder<TextEditingValue>(
      valueListenable: controller,
      builder: (context, value, _) {
        return AppTextField(
          controller: controller,
          hint: hint,
          autofocus: autofocus,
          prefixIcon: Icon(
            Icons.search,
            size: 18,
            color: scheme.onSurfaceVariant,
          ),
          suffixIcon: value.text.isEmpty
              ? null
              : IconButton(
                  tooltip: '清空搜索',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    controller.clear();
                    onChanged?.call('');
                  },
                  icon: Icon(
                    Icons.close,
                    size: 16,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
          onChanged: onChanged,
        );
      },
    );
  }
}
