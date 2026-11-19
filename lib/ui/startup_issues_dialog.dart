import 'package:material_ui/material_ui.dart';

import '../core/validate/validator.dart';
import 'app_dialog.dart';
import 'theme.dart';
import 'widgets/edit_dialog.dart';

/// 启动前语义自检未通过时的阻断弹窗。
///
/// 返回 true 表示用户在二次确认后仍要启动内核（调用方据此 `start(force: true)`）。
Future<bool> showStartupIssuesDialog(
  BuildContext context,
  ValidationReport report,
) async {
  final errors = report.errors;
  final wantsStart = await showAppDialog<bool>(
    context,
    width: dialogWidthOf(context),
    barrierDismissible: false,
    builder: (ctx) => EditDialog(
      title: '配置无法启动',
      subtitle: '配置里有 ${errors.length} 处引用不存在，内核加载时会直接退出。',
      content: SizedBox(
        width: double.maxFinite,
        height: 300,
        child: ListView.separated(
          itemCount: errors.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (ctx, i) => _StartupIssueTile(issue: errors[i]),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          child: const Text('仍然启动'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('返回编辑'),
        ),
      ],
    ),
  );
  if (wantsStart != true || !context.mounted) return false;
  final confirmed = await showConfirmDialog(
    context,
    title: '仍然启动内核？',
    message: '这些引用问题会让内核很可能加载失败并退出。建议先返回修改配置。',
    confirmLabel: '仍然启动',
    danger: true,
  );
  return confirmed == true;
}

class _StartupIssueTile extends StatelessWidget {
  const _StartupIssueTile({required this.issue});

  final Issue issue;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 18, color: scheme.error),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  issue.message,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                if (_pathLabel(issue.path) case final label?) ...[
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: Theme.of(context).textTheme.bodySmall
                        ?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 把内部路径翻成人话：`rules › 2` → 「规则第 3 行」。
  static String? _pathLabel(List<Object?> path) {
    if (path.isEmpty) return null;
    final first = '${path.first}';
    final index = path.length > 1 && path[1] is int ? path[1] as int : null;
    return switch (first) {
      'rules' when index != null => '规则第 ${index + 1} 行',
      'proxy-groups' when index != null => '策略组 #${index + 1}',
      'proxies' when index != null => '节点 #${index + 1}',
      _ => path.join(' › '),
    };
  }
}
