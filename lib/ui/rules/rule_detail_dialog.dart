import 'package:material_ui/material_ui.dart';

import '../../core/edit/rule_labels.dart';
import '../../core/model/profile.dart';
import '../theme.dart';
import '../app_dialog.dart';
import '../widgets/edit_dialog.dart';

/// 规则详情：行内只放得下一行，完整名字 / payload / 目标都在这里看。
Future<void> showRuleDetailDialog(
  BuildContext context, {
  required RuleEntry rule,
  VoidCallback? onEdit,
  VoidCallback? onMoveToGroup,
}) {
  return showAppDialog<void>(
    context,
    width: dialogWidthOf(context),
    builder: (ctx) => EditDialog(
      title: '规则详情',
      subtitle: '行内只显示一行，完整内容在这里',
      confirmLabel: '关闭',
      showCancel: false,
      actions: [
        if (onMoveToGroup != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onMoveToGroup();
            },
            icon: const Icon(Icons.swap_horiz, size: 18),
            label: const Text('换组'),
          ),
        if (onEdit != null)
          TextButton.icon(
            onPressed: () {
              Navigator.pop(ctx);
              onEdit();
            },
            icon: const Icon(Icons.edit_outlined, size: 18),
            label: const Text('编辑'),
          ),
      ],
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _DetailRow(label: '名称', value: ruleTitleOf(rule), monoFont: false),
          _DetailRow(label: '类型', value: rule.type, monoFont: true),
          _DetailRow(
            label: '匹配内容',
            value: rule.payload.isEmpty ? '（无，兜底规则）' : rule.payload,
            monoFont: true,
          ),
          _DetailRow(label: '目标', value: rule.target, monoFont: true),
          if (rule.isTerminal)
            _DetailRow(
              label: '说明',
              value: 'MATCH 必须放在最后，接住未匹配流量。',
              monoFont: false,
            ),
          if (rule.noResolve)
            const _DetailRow(label: '选项', value: 'no-resolve', monoFont: true),
        ],
      ),
    ),
  );
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({
    required this.label,
    required this.value,
    required this.monoFont,
  });

  final String label;
  final String value;
  final bool monoFont;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: Insets.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: mono(10, color: scheme.onSurfaceVariant, weight: 600),
          ),
          const SizedBox(height: 4),
          SelectableText(
            value,
            style: monoFont
                ? mono(12.5, color: scheme.onSurface)
                : display(13.5, weight: 600),
          ),
        ],
      ),
    );
  }
}
