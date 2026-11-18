import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../app_dialog.dart';
import '../theme.dart';

/// 编辑弹窗的内容区最大高度：屏高 80%，最多 720。
double editDialogMaxHeight(BuildContext context) =>
    math.min(MediaQuery.sizeOf(context).height * 0.8, 720);

/// 确认弹窗宽度：最多 400，小屏留 64 的边距。
double confirmDialogWidth(BuildContext context) =>
    math.min(400, math.max(0, MediaQuery.sizeOf(context).width - 64));

/// 统一编辑弹窗：标题行 + 内容区（可滚） + 按钮区（固定）。
///
/// 结构见 docs/DESIGN_SYSTEM.md「弹窗规范 / A. 编辑类弹窗」：
/// - 宽度由 `showEditDialog` 传入 `showAppDialog(width: dialogWidthOf(...))`；
/// - 高度自适应，封顶 [editDialogMaxHeight]；超高只滚内容；
/// - 底部按钮右对齐，最多两个；删除放内容左下角，不进按钮区。
class EditDialog extends StatelessWidget {
  const EditDialog({
    super.key,
    required this.title,
    required this.content,
    this.subtitle,
    this.confirmLabel = '保存',
    this.cancelLabel = '取消',
    this.onConfirm,
    this.onCancel,
    this.onDelete,
    this.danger = false,
  });

  final String title;
  final String? subtitle;
  final Widget content;
  final String confirmLabel;
  final String cancelLabel;
  final VoidCallback? onConfirm;
  final VoidCallback? onCancel;
  final VoidCallback? onDelete;

  /// 主按钮用 error 色（例如「覆盖」这类破坏性保存）。
  final bool danger;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(Radiuses.xl);
    return ConstrainedBox(
      key: const ValueKey('edit-dialog'),
      constraints: BoxConstraints(maxHeight: editDialogMaxHeight(context)),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(borderRadius: radius),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                Insets.lg,
                Insets.sm,
                Insets.md,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: const TextStyle(
                            fontSize: 20,
                            fontWeight: FontWeight.w600,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: Insets.xs),
                          Text(
                            subtitle!,
                            style: TextStyle(
                              fontSize: 13,
                              color: scheme.onSurfaceVariant.withValues(
                                alpha: 0.8,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: '关闭',
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: onCancel ?? () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
                ],
              ),
            ),
            const Divider(height: 1),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  Insets.xl,
                  Insets.lg + Insets.xs,
                  Insets.xl,
                  Insets.lg + Insets.xs,
                ),
                child: content,
              ),
            ),
            const Divider(height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.xl,
                Insets.lg,
                Insets.xl,
                Insets.lg,
              ),
              child: Row(
                children: [
                  if (onDelete != null)
                    TextButton.icon(
                      onPressed: onDelete,
                      icon: const Icon(Icons.delete_outline, size: 18),
                      label: const Text('删除'),
                      style: TextButton.styleFrom(
                        foregroundColor: scheme.error,
                      ),
                    ),
                  const Spacer(),
                  TextButton(
                    onPressed: onCancel ?? () => Navigator.of(context).pop(),
                    child: Text(cancelLabel),
                  ),
                  const SizedBox(width: Insets.md),
                  FilledButton(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, 44),
                      backgroundColor: danger ? scheme.error : null,
                      foregroundColor: danger ? scheme.onError : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 打开统一编辑弹窗；确认返回 true，取消/关闭返回 false/null。
Future<bool?> showEditDialog(
  BuildContext context, {
  required String title,
  String? subtitle,
  required Widget content,
  String confirmLabel = '保存',
  String cancelLabel = '取消',
  bool danger = false,
  bool barrierDismissible = true,
  VoidCallback? onDelete,
}) {
  return showAppDialog<bool>(
    context,
    width: dialogWidthOf(context),
    barrierDismissible: barrierDismissible,
    builder: (ctx) => EditDialog(
      title: title,
      subtitle: subtitle,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      onDelete: onDelete == null
          ? null
          : () {
              onDelete();
              Navigator.of(ctx).pop(false);
            },
      onCancel: () => Navigator.of(ctx).pop(false),
      onConfirm: () => Navigator.of(ctx).pop(true),
      content: content,
    ),
  );
}

/// 统一确认弹窗：宽 min(400, 屏宽-64)，不可点外关闭。
Future<bool?> showConfirmDialog(
  BuildContext context, {
  required String title,
  String? message,
  String confirmLabel = '确定',
  String cancelLabel = '取消',
  bool danger = false,
}) {
  return showAppDialog<bool>(
    context,
    width: confirmDialogWidth(context),
    barrierDismissible: false,
    builder: (ctx) => _ConfirmDialog(
      title: title,
      message: message,
      confirmLabel: confirmLabel,
      cancelLabel: cancelLabel,
      danger: danger,
      onCancel: () => Navigator.of(ctx).pop(false),
      onConfirm: () => Navigator.of(ctx).pop(true),
    ),
  );
}

class _ConfirmDialog extends StatelessWidget {
  const _ConfirmDialog({
    required this.title,
    required this.message,
    required this.confirmLabel,
    required this.cancelLabel,
    required this.danger,
    required this.onCancel,
    required this.onConfirm,
  });

  final String title;
  final String? message;
  final String confirmLabel;
  final String cancelLabel;
  final bool danger;
  final VoidCallback onCancel;
  final VoidCallback onConfirm;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      key: const ValueKey('confirm-dialog'),
      constraints: BoxConstraints(maxWidth: confirmDialogWidth(context)),
      child: Material(
        color: scheme.surfaceContainerHigh,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radiuses.xl),
        ),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.lg + Insets.xs,
            Insets.xl,
            Insets.lg,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.w600,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              if (message != null) ...[
                const SizedBox(height: Insets.sm),
                Text(
                  message!,
                  style: TextStyle(
                    fontSize: 13,
                    color: scheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: Insets.xl),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(onPressed: onCancel, child: Text(cancelLabel)),
                  const SizedBox(width: Insets.md),
                  FilledButton(
                    onPressed: onConfirm,
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(96, 44),
                      backgroundColor: danger ? scheme.error : null,
                      foregroundColor: danger ? scheme.onError : null,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(confirmLabel),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
