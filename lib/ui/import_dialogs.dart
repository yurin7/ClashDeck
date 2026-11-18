import 'package:material_ui/material_ui.dart';

import '../core/parse/share_link.dart';
import '../core/parse/subscription.dart';
import '../core/yaml/yaml_doc.dart';
import 'theme.dart';
import 'fields.dart';
import 'widgets.dart';
import 'widgets/edit_dialog.dart';

/// 「粘贴分享链接」对话框：多行输入，返回原文；取消返回 null。
Future<String?> showPasteLinksDialog(
  BuildContext context, {
  String? initial,
  String title = '粘贴分享链接',
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showAppDialog<String>(
    context,
    width: dialogWidthOf(context),
    builder: (ctx) => EditDialog(
      title: title,
      confirmLabel: '解析',
      cancelLabel: '取消',
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextArea(
            controller: ctrl,
            autofocus: true,
            monospace: true,
            label: '一行一个链接，可以混着来',
            hint: 'vless://…\nvmess://…\nhysteria2://…',
          ),
          const SizedBox(height: 8),
          Text(
            '支持 ${supportedSchemes.join(' / ')}；'
            '也可以直接粘贴整段 base64 订阅内容。',
            style: Theme.of(ctx).textTheme.bodySmall,
          ),
        ],
      ),
      onCancel: () => Navigator.pop(ctx),
      onConfirm: () => Navigator.pop(ctx, ctrl.text),
    ),
  ).whenComplete(() => disposeAfterDialog(ctrl));
}

/// 「从订阅链接导入」对话框的返回值。
class SubscriptionInput {
  const SubscriptionInput({required this.url, this.result});

  final String url;

  /// 选择「同步」并拉取成功后的结果；选「稍后」只保存地址时为 null。
  final SubscriptionResult? result;
}

final RegExp _subscriptionUrlPattern = RegExp(r'^https?://\S+$');

/// 订阅对话框：只收地址，点「保存」后再问要不要立即同步。
///
/// 选「稍后」只返回地址（由调用方保存，不联网）；选「同步」才拉取，
/// 拉取失败就地显示错误、不关窗、不丢已填地址。
Future<SubscriptionInput?> showSubscriptionDialog(
  BuildContext context, {
  String? initialUrl,
  Future<SubscriptionResult> Function(String url)? fetch,
}) {
  return showAppDialog<SubscriptionInput>(
    context,
    width: dialogWidthOf(context),
    builder: (_) => _SubscriptionDialog(
      initialUrl: initialUrl,
      fetch: fetch ?? fetchSubscription,
    ),
  );
}

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog({required this.initialUrl, required this.fetch});

  final String? initialUrl;
  final Future<SubscriptionResult> Function(String url) fetch;

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialUrl ?? '',
  );
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '先填订阅地址');
      return;
    }
    if (!_subscriptionUrlPattern.hasMatch(url)) {
      setState(() => _error = '地址需要以 http:// 或 https:// 开头');
      return;
    }
    setState(() => _error = null);

    final syncNow = await showConfirmDialog(
      context,
      title: '是否立即同步此订阅？',
      message: '同步会立刻拉取节点写入配置；选「稍后」只保存地址，之后也能再同步。',
      confirmLabel: '同步',
      cancelLabel: '稍后',
    );
    if (!mounted) return;
    if (syncNow != true) {
      Navigator.pop(context, SubscriptionInput(url: url));
      return;
    }

    setState(() => _busy = true);
    try {
      final result = await widget.fetch(url);
      if (!mounted) return;
      Navigator.pop(context, SubscriptionInput(url: url, result: result));
    } on ConfigEditException catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.message;
        _busy = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '拉取失败：$e';
        _busy = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return EditDialog(
      title: '订阅链接',
      confirmLabel: '保存',
      onConfirm: () {
        _save();
      },
      onCancel: () => Navigator.pop(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextArea(
            controller: _url,
            autofocus: true,
            enabled: !_busy,
            label: '订阅地址',
            hint: 'https://example.com/api/v1/client/subscribe?token=…',
          ),
          if (_busy) ...[
            const SizedBox(height: Insets.md),
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('正在同步…'),
              ],
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Insets.md),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: theme.colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(Radiuses.sm),
              ),
              child: Text(
                _error!,
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onErrorContainer,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
