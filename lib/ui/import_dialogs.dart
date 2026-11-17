import 'package:material_ui/material_ui.dart';

import '../core/parse/share_link.dart';
import '../core/parse/subscription.dart';
import '../core/yaml/yaml_doc.dart';
import 'theme.dart';
import 'dropdown.dart';
import 'widgets.dart';

/// 「粘贴分享链接」对话框：多行输入，返回原文；取消返回 null。
Future<String?> showPasteLinksDialog(
  BuildContext context, {
  String? initial,
  String title = '粘贴分享链接',
}) {
  final ctrl = TextEditingController(text: initial ?? '');
  return showAppDialog<String>(
    context,
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
/// 目标组用统一的下拉控件选：默认「用规则集名称」（direct.txt → direct），
/// 也可以直接挑一个已有组，或者选「自定义…」现写一个名字。弹窗只留一行提示，
/// 具体怎么解析交给导入逻辑，不再在对话框里堆说明。
Future<RuleImportInput?> showRuleImportDialog(
  BuildContext context, {
  String? initial,
  List<String> groups = const [],
}) {
  return showAppDialog<RuleImportInput>(
    context,
    builder: (ctx) => _RuleImportDialog(initial: initial, groups: groups),
  );
}

class _RuleImportDialog extends StatefulWidget {
  const _RuleImportDialog({this.initial, required this.groups});

  final String? initial;
  final List<String> groups;

  @override
  State<_RuleImportDialog> createState() => _RuleImportDialogState();
}

class _RuleImportDialogState extends State<_RuleImportDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial ?? '',
  );
  final TextEditingController _customCtrl = TextEditingController();
  String _group = '';

  bool _isCustom = false;

  @override
  void dispose() {
    _ctrl.dispose();
    _customCtrl.dispose();
    super.dispose();
  }

  String get _groupValue => _isCustom ? _customCtrl.text.trim() : _group;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final maxHeight = MediaQuery.sizeOf(context).height * 0.62;

    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('导入规则')),
          IconButton(
            tooltip: '常用规则集',
            visualDensity: VisualDensity.compact,
            onPressed: () => Navigator.pop(
              context,
              const RuleImportInput(text: '', group: '', preset: true),
            ),
            icon: const Icon(Icons.auto_awesome, size: 20),
          ),
        ],
      ),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _ctrl,
                minLines: 5,
                maxLines: 8,
                autofocus: false,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                decoration: const InputDecoration(
                  labelText: '规则行、配置片段，或规则集地址',
                  hintText:
                      'DOMAIN-SUFFIX,google.com,PROXY\nhttps://…/direct.txt',
                  helperText: '支持规则行、YAML 片段、规则集 URL',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              AppDropdown<String>(
                value: _group,
                label: '目标组',
                helper: '规则集地址导入时用',
                expand: true,
                enabled: !_isCustom,
                options: [
                  const DropdownOption('', '（默认）用规则集名称'),
                  for (final name in widget.groups) DropdownOption(name, name),
                ],
                onChanged: (value) => setState(() => _group = value),
              ),
              if (_isCustom) ...[
                const SizedBox(height: 8),
                TextField(
                  controller: _customCtrl,
                  autofocus: true,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: '自定义组名',
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
              const SizedBox(height: 4),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () => setState(() {
                    _isCustom = !_isCustom;
                    _customCtrl.clear();
                  }),
                  child: Text(
                    _isCustom ? '用已有组' : '自定义组名',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: scheme.primary,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(
            context,
            RuleImportInput(text: _ctrl.text, group: _groupValue),
          ),
          child: const Text('导入'),
        ),
      ],
    );
  }
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
