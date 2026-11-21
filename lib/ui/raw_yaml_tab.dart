import 'package:material_ui/material_ui.dart';

import '../state/editor_state.dart';
import 'widgets.dart';
import 'fields.dart';
import 'theme.dart';
import './widgets/edit_dialog.dart';

/// 只读 YAML 源码视图 + 整体替换编辑。
class RawYamlTab extends StatelessWidget {
  const RawYamlTab({super.key, required this.state, this.inline = false});

  final EditorState state;
  final bool inline;

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
    if (inline) return _InlineYamlEditor(state: state);

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

class _InlineYamlEditor extends StatefulWidget {
  const _InlineYamlEditor({required this.state});

  final EditorState state;

  @override
  State<_InlineYamlEditor> createState() => _InlineYamlEditorState();
}

class _InlineYamlEditorState extends State<_InlineYamlEditor> {
  late final _controller = TextEditingController(text: widget.state.doc.text);

  @override
  void didUpdateWidget(covariant _InlineYamlEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    final text = widget.state.doc.text;
    if (_controller.text == text) return;
    final offset = _controller.selection.extentOffset.clamp(0, text.length);
    _controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: offset),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceContainerLow,
            border: Border.all(color: colors.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 11, 14, 10),
                child: Text(
                  '${'\n'.allMatches(_controller.text).length + 1} 行',
                  style: mono(11, color: colors.onSurfaceVariant),
                ),
              ),
              const Hairline(),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: AppTextField(
                    controller: _controller,
                    expands: true,
                    keyboardType: TextInputType.multiline,
                    textAlignVertical: TextAlignVertical.top,
                    autocorrect: false,
                    enableSuggestions: false,
                    style: mono(13, color: colors.onSurface),
                    onChanged: widget.state.replaceText,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
