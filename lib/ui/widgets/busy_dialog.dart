import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// 阻塞式「正在…」弹窗：只有进度与说明，没有标题和确认按钮。
///
/// 由 `showAppDialog(barrierDismissible: false)` 承载。
class BusyDialog extends StatelessWidget {
  const BusyDialog({
    super.key,
    required this.message,
    this.progress,
    this.onCancel,
  });

  final String message;
  final ValueListenable<String>? progress;

  /// 传 null 表示不可取消（默认）。
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final listenable = progress;
    return Dialog(
      backgroundColor: scheme.surfaceContainerHigh,
      insetPadding: const EdgeInsets.all(Insets.lg),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.xl),
      ),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 300, maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(Insets.lg),
          child: listenable == null
              ? _content(context, '')
              : ValueListenableBuilder<String>(
                  valueListenable: listenable,
                  builder: (_, extra, _) => _content(context, extra),
                ),
        ),
      ),
    );
  }

  Widget _content(BuildContext context, String extra) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: Insets.md),
            Expanded(child: Text(message)),
          ],
        ),
        if (extra.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: Insets.sm),
            child: Text(extra, style: hintStyle(context)),
          ),
        if (onCancel != null)
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(onPressed: onCancel, child: const Text('取消')),
          ),
      ],
    );
  }
}
