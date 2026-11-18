import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update/update_check.dart';
import 'app_dialog.dart';
import 'theme.dart';
import 'widgets/edit_dialog.dart';

/// 「发现新版本」弹窗：版本号 + 发布日期 + 更新说明（最多 6 行滚动）+ 去下载 / 取消。
///
/// 只跳浏览器打开 Release 页，不在应用内下载；[openUrl] 可注入，测试不联网。
Future<bool> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  Future<bool> Function(String url)? openUrl,
}) async {
  final opened = await showAppDialog<bool>(
    context,
    width: dialogWidthOf(context),
    builder: (ctx) => EditDialog(
      title: '发现新版本',
      subtitle: '当前 ${info.version} 已发布',
      confirmLabel: '去下载',
      cancelLabel: '取消',
      content: _UpdateBody(info: info),
      onCancel: () => Navigator.pop(ctx, false),
      onConfirm: () async {
        final launcher =
            openUrl ??
            (url) =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
        final ok = info.url.isEmpty ? false : await launcher(info.url);
        if (ctx.mounted) Navigator.pop(ctx, ok);
      },
    ),
  );
  return opened ?? false;
}

class _UpdateBody extends StatelessWidget {
  const _UpdateBody({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = info.publishedAt;
    final dateLabel = date == null
        ? null
        : '${date.year}-${_two(date.month)}-${_two(date.day)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radiuses.chip.x),
              ),
              child: Text(
                'v${info.version}',
                style: display(13, weight: 700, color: scheme.primary),
              ),
            ),
            if (dateLabel != null) ...[
              const SizedBox(width: Insets.sm),
              Text(dateLabel, style: hintStyle(context)),
            ],
          ],
        ),
        const SizedBox(height: Insets.md),
        // 纯文本、最多 6 行高，超出在框内滚动（不随弹窗变高）。
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 132),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Text(info.notes.isEmpty ? '这次没有写更新说明。' : info.notes),
            ),
          ),
        ),
      ],
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
