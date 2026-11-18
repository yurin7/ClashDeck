import 'package:material_ui/material_ui.dart';

import 'edit_dialog.dart';

/// 统一的删除确认：配置/策略组/规则/节点四个入口共用。
///
/// 只要走删除，就必须经过这里，保证：
/// - 危险操作按钮固定 error 色（`danger: true`）；
/// - 主按钮固定「删除」，取消固定「取消」；
/// - 影响面（组引用、不可恢复…）用 [extraHint] 追加在正文后，行为一致。
///
/// 返回 true 表示用户确认删除。
Future<bool> confirmDelete(
  BuildContext context, {
  required String title,
  required String message,
  String? extraHint,
  String confirmLabel = '删除',
}) async {
  final detail = extraHint == null || extraHint.isEmpty
      ? message
      : '$message\n\n$extraHint';
  final confirmed = await showConfirmDialog(
    context,
    title: title,
    message: detail,
    confirmLabel: confirmLabel,
    danger: true,
  );
  return confirmed == true;
}
