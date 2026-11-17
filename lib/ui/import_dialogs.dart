import 'package:material_ui/material_ui.dart';

import '../core/parse/share_link.dart';
import '../core/parse/subscription.dart';
import '../core/yaml/yaml_doc.dart';
import 'theme.dart';
import 'widgets.dart';

/// 「粘贴分享链接」对话框：多行输入，返回原文；取消返回 null。
Future<String?> showPasteLinksDialog(
  BuildContext context, {
  String? initial,
  String title = '粘贴分享链接',
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              minLines: 6,
              maxLines: 12,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: '一行一个链接，可以混着来',
                hintText: 'vless://…\nvmess://…\nhysteria2://…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '支持 ${supportedSchemes.join(' / ')}；'
              '也可以直接粘贴整段 base64 订阅内容。',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, ctrl.text),
          child: const Text('解析'),
        ),
      ],
    ),
  );
}

/// 「导入规则」对话框的返回值。
class RuleImportInput {
  const RuleImportInput({
    required this.text,
    required this.group,
    this.preset = false,
  });

  /// 规则行 / 配置片段 / 规则集地址。
  final String text;

  /// 目标组名：留空表示「用规则集自己的名字」（如 direct.txt → direct）。
  final String group;

  /// 用户点的是「常用规则集」，不是粘贴内容。
  final bool preset;
}

/// 「导入规则」对话框：粘贴规则行 / 配置片段 / 规则集地址。
///
/// 组名输入框默认留空，只有填了单个规则集地址时才有意义：留空就用规则集名字
/// （direct.txt → direct），同名组不存在会自动建，存在就直接附加进去。右侧箭头
/// 列出当前配置里已有的组，点一下覆盖输入框，避免「选组」和「建组」两套交互。
Future<RuleImportInput?> showRuleImportDialog(
  BuildContext context, {
  String? initial,
  List<String> groups = const [],
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  final groupCtrl = TextEditingController();
  return showDialog<RuleImportInput>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('导入规则'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: ctrl,
              minLines: 8,
              maxLines: 14,
              autofocus: true,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
              decoration: const InputDecoration(
                labelText: '规则行、配置片段，或规则集地址',
                hintText:
                    'DOMAIN-SUFFIX,google.com,PROXY\n'
                    'GEOIP,CN,DIRECT,no-resolve\n'
                    'MATCH,PROXY\n'
                    'https://…/direct.txt',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: groupCtrl,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              decoration: InputDecoration(
                labelText: '目标组',
                hintText: '留空 = 用规则集名称',
                helperText: groups.isEmpty
                    ? '规则集地址导入时用；同名组不存在会自动新建'
                    : '规则集地址导入时用；右侧箭头可挑已有组',
                border: const OutlineInputBorder(),
                suffixIcon: groups.isEmpty
                    ? const Icon(Icons.expand_more, size: 18)
                    : PopupMenuButton<String>(
                        tooltip: '选择已有组',
                        icon: const Icon(Icons.expand_more, size: 18),
                        onSelected: (value) => groupCtrl.text = value,
                        itemBuilder: (_) => [
                          for (final name in groups)
                            PopupMenuItem(value: name, child: Text(name)),
                        ],
                      ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '认 YAML 片段里的 rules / proxy-groups / rule-providers / '
              'proxy-providers：策略组会一起合并（成员在当前配置里不存在就跳过），'
              '规则会插到 MATCH 之前，重复的自动跳过。\n'
              '只填一个 URL 时按规则集处理（Loyalsoldier/clash-rules 这类 '
              'payload 列表），会自动建 rule-providers 并加一条 RULE-SET。',
              style: Theme.of(ctx).textTheme.bodySmall,
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: () => Navigator.pop(
            ctx,
            const RuleImportInput(text: '', group: '', preset: true),
          ),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: const Text('常用规则集'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            ctx,
            RuleImportInput(text: ctrl.text, group: groupCtrl.text.trim()),
          ),
          child: const Text('导入'),
        ),
      ],
    ),
  );
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
  return showDialog<SubscriptionInput>(
    context: context,
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
    return AlertDialog(
      title: const Text('从订阅链接导入'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _url,
              keyboardType: TextInputType.url,
              autocorrect: false,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '订阅地址',
                hintText: 'https://example.com/api/v1/client/subscribe?token=…',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        if (widget.allowSaveOnly)
          TextButton(
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
        FilledButton(
          onPressed: _busy
              ? null
              : () {
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
          child: Text(_result == null ? '拉取' : '导入'),
        ),
      ],
    );
  }
}
