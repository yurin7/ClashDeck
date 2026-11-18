import 'package:material_ui/material_ui.dart';

import '../widgets.dart';
import '../fields.dart';
import 'edit_dialog.dart';

/// 单输入（或少量多行）弹窗：设置页、配置命名、粘贴导入共用。
///
/// 尺寸与 [EditDialog] 一致（宽 min(520, 屏宽-64)），输入框撑满内容区。
Future<String?> showTextInputDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  String initial = '',
  String? label,
  String? hint,
  String? helper,
  bool monospace = false,

  /// 多行链接/大段文本用多行文本域（宽度撑满、高度约 0.8×宽度、框内滚动）。
  bool area = false,
  int minLines = 1,
  int? maxLines,
  String confirmLabel = '保存',
  String cancelLabel = '取消',
}) {
  final controller = TextEditingController(text: initial);
  final result = showAppDialog<String>(
    context,
    width: dialogWidthOf(context),
    builder: (ctx) => EditDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      onConfirm: () => Navigator.of(ctx).pop(controller.text.trim()),
      onCancel: () => Navigator.of(ctx).pop(),
      content: area
          ? AppTextArea(
              controller: controller,
              autofocus: true,
              label: label,
              hint: hint,
              helper: helper,
              monospace: monospace,
            )
          : AppTextField(
              controller: controller,
              autofocus: true,
              label: label,
              hint: hint,
              helper: helper,
              minLines: minLines,
              maxLines: maxLines ?? (minLines > 1 ? minLines : 1),
              style: monospace
                  ? const TextStyle(fontFamily: 'monospace', fontSize: 12)
                  : null,
            ),
    ),
  );
  disposeAfterDialog(controller);
  return result;
}
