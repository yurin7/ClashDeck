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
          AppTextField(
            controller: ctrl,
            minLines: 6,
            maxLines: 12,
            autofocus: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            label: '一行一个链接，可以混着来',
            hint: 'vless://…\nvmess://…\nhysteria2://…',
            alignLabelWithHint: true,
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

  /// 点「拉取并导入」成功后的结果；只用「保存地址」时为 null。
  final SubscriptionResult? result;
}

/// 订阅对话框：填 URL → 拉取 → 显示节点数与用量 → 确认。
///
/// 网络与解析错误就地显示在对话框里（不关窗、不丢用户已填的地址）。
Future<SubscriptionInput?> showSubscriptionDialog(
  BuildContext context, {
  String? initialUrl,
  bool allowSaveOnly = true,
}) {
  return showAppDialog<SubscriptionInput>(
    context,
    width: dialogWidthOf(context),
    builder: (_) => _SubscriptionDialog(
      initialUrl: initialUrl,
      allowSaveOnly: allowSaveOnly,
    ),
  );
}

class _SubscriptionDialog extends StatefulWidget {
  const _SubscriptionDialog({
    required this.initialUrl,
    required this.allowSaveOnly,
  });

  final String? initialUrl;
  final bool allowSaveOnly;

  @override
  State<_SubscriptionDialog> createState() => _SubscriptionDialogState();
}

class _SubscriptionDialogState extends State<_SubscriptionDialog> {
  late final TextEditingController _url = TextEditingController(
    text: widget.initialUrl ?? '',
  );
  bool _busy = false;
  String? _error;
  SubscriptionResult? _result;

  @override
  void dispose() {
    _url.dispose();
    super.dispose();
  }

  Future<void> _fetch() async {
    final url = _url.text.trim();
    if (url.isEmpty) {
      setState(() => _error = '先填订阅地址');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await fetchSubscription(url);
      if (!mounted) return;
      setState(() {
        _result = result;
        _busy = false;
      });
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
    final result = _result;
    return EditDialog(
      title: '从订阅链接导入',
      confirmLabel: _result == null ? '拉取' : '导入',
      onConfirm: () {
        final result = _result;
        if (result == null) {
          _fetch();
          return;
        }
        Navigator.pop(
          context,
          SubscriptionInput(url: _url.text.trim(), result: result),
        );
      },
      onCancel: () => Navigator.pop(context),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AppTextField(
            controller: _url,
            keyboardType: TextInputType.url,
            enabled: !_busy,
            label: '订阅地址',
            hint: 'https://example.com/api/v1/client/subscribe?token=…',
            alignLabelWithHint: true,
          ),
          const SizedBox(height: Insets.md),
          if (_busy)
            const Row(
              children: [
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('正在拉取…'),
              ],
            ),
          if (_error != null)
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
          if (result != null) ...[
            Row(
              children: [
                Pill(
                  label: '${result.count} 个节点',
                  icon: Icons.check,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: Insets.sm),
                Expanded(
                  child: Text(
                    result.title ?? '订阅内容已解析',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
            if (result.usage != null && result.usage!.label.isNotEmpty) ...[
              const SizedBox(height: Insets.sm),
              Text(result.usage!.label, style: theme.textTheme.bodySmall),
            ],
            if (result.yamlConfig != null) ...[
              const SizedBox(height: Insets.sm),
              Text(
                '这是一份完整配置，导入时只取其中的 proxies（组和规则不动）。',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
          if (widget.allowSaveOnly)
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _busy
                    ? null
                    : () {
                        final url = _url.text.trim();
                        if (url.isEmpty) {
                          setState(() => _error = '先填订阅地址');
                          return;
                        }
                        Navigator.pop(context, SubscriptionInput(url: url));
                      },
                child: const Text('只保存地址'),
              ),
            ),
        ],
      ),
    );
  }
}
