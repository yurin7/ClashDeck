import 'package:material_ui/material_ui.dart';

import '../state/editor_state.dart';
import 'widgets.dart';
import 'fields.dart';
import './widgets/edit_dialog.dart';

/// 只读 YAML 源码视图 + 整体替换编辑。
class RawYamlTab extends StatelessWidget {
  const RawYamlTab({super.key, required this.state});

  final EditorState state;

  Future<void> _editRaw(BuildContext context) async {
    final ctrl = TextEditingController(text: state.doc.text);
    final result = await showAppDialog<String>(
      context,
      width: dialogWidthOf(context),
      builder: (ctx) => EditDialog(
        title: '编辑 YAML 源码',
        confirmLabel: '应用',
        content: SizedBox(
          width: double.maxFinite,
          height: 420,
          child: AppTextField(
            controller: ctrl,
            expands: true,
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              hintText: '整段配置…',
            ),
          ),
        ),
        onCancel: () => Navigator.pop(ctx),
        onConfirm: () => Navigator.pop(ctx, ctrl.text),
      ),
    );
    disposeAfterDialog(ctrl);
    if (result == null || result == state.doc.text) return;
    state.replaceText(result);
    if (!context.mounted) return;
    if (!state.isValidYaml) {
      showToast(context, 'YAML 解析失败：${state.doc.error?.message ?? '未知错误'}');
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final lines = state.doc.text.split('\n');
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 8, 4),
          child: Row(
            children: [
              Icon(Icons.code, size: 18, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '${lines.length} 行 · 注释与未知字段都会原样保留',
                  style: Theme.of(context).textTheme.bodySmall
                      ?.copyWith(color: scheme.outline),
                ),
              ),
              TextButton.icon(
                onPressed: () => _editRaw(context),
                icon: const Icon(Icons.edit_outlined, size: 18),
                label: const Text('编辑'),
              ),
            ],
          ),
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: SelectableText(
                state.doc.text,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
