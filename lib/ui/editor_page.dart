import 'package:material_ui/material_ui.dart';

import '../core/validate/validator.dart';
import '../data/profile_store.dart';
import '../state/editor_state.dart';
import 'import_dialogs.dart';
import 'proxy_board.dart';
import 'raw_yaml_tab.dart';
import 'rules_tab.dart';
import 'runtime_page.dart';
import 'theme.dart';
import 'widgets.dart';

/// 单个配置的编辑器外壳：撤销/重做/保存 + 代理/规则/源码三个页签。
class EditorPage extends StatefulWidget {
  const EditorPage({
    super.key,
    required this.store,
    required this.fileName,
    this.initialText,
    this.displayName,
  });

  final ProfileStore store;
  final String fileName;

  /// 给定则不再从磁盘读，直接作为初始内容（新建/导入流程用）。
  final String? initialText;
  final String? displayName;

  @override
  State<EditorPage> createState() => _EditorPageState();
}

class _EditorPageState extends State<EditorPage> {
  EditorState? _state;
  String? _loadError;
  bool _saving = false;

  String get _title => widget.displayName ?? widget.fileName;

  @override
  void initState() {
    super.initState();
    final text = widget.initialText;
    if (text != null) {
      _state = EditorState.fromText(
        text,
        fileName: widget.fileName,
        savedText: text,
      );
    } else {
      _load();
    }
  }

  Future<void> _load() async {
    try {
      final text = await widget.store.read(widget.fileName);
      if (!mounted) return;
      setState(() {
        _state = EditorState.fromText(text, fileName: widget.fileName);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _loadError = '$e');
    }
  }

  Future<void> _save() async {
    final state = _state;
    if (state == null) return;
    setState(() => _saving = true);
    try {
      await state.save(widget.store);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('已保存')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('保存失败：$e')));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _saveAs() async {
    final state = _state;
    if (state == null) return;
    final name = await showDialog<String>(
      context: context,
      builder: (_) => _NameDialog(initial: '$_title 副本'),
    );
    if (name == null || name.isEmpty) return;
    try {
      await state.saveAs(widget.store, name);
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('已另存为「$name」')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text('另存为失败：$e')));
    }
  }

  /// 记住订阅地址（写 sidecar meta，不进 YAML）。
  Future<void> _rememberSubscription(String url) async {
    try {
      await widget.store.setSubscriptionUrl(widget.fileName, url);
    } catch (_) {
      // meta 只是记账，写不进去不影响配置文件本身。
    }
  }

  /// 菜单里的「订阅…」：显示已存地址，可重新拉取（按名字跳过已存在的节点）。
  Future<void> _subscription() async {
    final state = _state;
    if (state == null) return;
    String? saved;
    try {
      saved = await widget.store.subscriptionUrl(widget.fileName);
    } catch (_) {
      saved = null;
    }
    if (!mounted) return;
    final input = await showSubscriptionDialog(context, initialUrl: saved);
    if (input == null || !mounted) return;

    await _rememberSubscription(input.url);
    final result = input.result;
    if (result == null) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(const SnackBar(content: Text('订阅地址已保存')));
      return;
    }
    // 刷新语义：同名节点跳过，新节点追加（不覆盖用户改过的节点）。
    if (!state.importProxyList(result.proxies, skipExisting: true)) {
      final err = state.lastError;
      if (!mounted) return;
      ScaffoldMessenger.of(context)
        ..clearSnackBars()
        ..showSnackBar(SnackBar(content: Text(err ?? '导入失败')));
      return;
    }
    final added = state.profile.proxies.length;
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(SnackBar(content: Text('订阅已更新：现有 $added 个节点（同名跳过）')));
  }

  Future<void> _showIssues(ValidationReport report) async {
    await showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          report.isClean
              ? '校验通过'
              : '${report.errors.length} 个错误 · ${report.warnings.length} 个警告',
        ),
        content: SizedBox(
          width: double.maxFinite,
          height: 360,
          child: report.isClean
              ? const Align(
                  alignment: Alignment.topLeft,
                  child: Text('没有发现问题。'),
                )
              : ListView.separated(
                  itemCount: report.issues.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (ctx, i) {
                    final issue = report.issues[i];
                    final scheme = Theme.of(ctx).colorScheme;
                    final color = switch (issue.severity) {
                      IssueSeverity.error => scheme.error,
                      IssueSeverity.warning => scheme.tertiary,
                      IssueSeverity.info => scheme.outline,
                    };
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        switch (issue.severity) {
                          IssueSeverity.error => Icons.error_outline,
                          IssueSeverity.warning => Icons.warning_amber_outlined,
                          IssueSeverity.info => Icons.info_outline,
                        },
                        color: color,
                        size: 20,
                      ),
                      title: Text(
                        issue.message,
                        style: TextStyle(color: color),
                      ),
                      subtitle: Text(
                        issue.path.isEmpty ? '/' : issue.path.join(' › '),
                      ),
                    );
                  },
                ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final error = _loadError;
    if (error != null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.error_outline,
                  size: 40,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(height: 12),
                Text('读取失败\n$error', textAlign: TextAlign.center),
                const SizedBox(height: 16),
                FilledButton(onPressed: _load, child: const Text('重试')),
              ],
            ),
          ),
        ),
      );
    }

    final state = _state;
    if (state == null) {
      return Scaffold(
        appBar: AppBar(title: Text(_title)),
        body: const Center(child: CircularProgressIndicator()),
      );
    }

    return ListenableBuilder(
      listenable: state,
      builder: (context, _) => DefaultTabController(
        length: 3,
        child: Scaffold(
          appBar: AppBar(
            titleSpacing: 8,
            title: Row(
              children: [
                Flexible(
                  child: Text(
                    _title,
                    style: display(17, weight: 600),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (state.dirty) ...[
                  const SizedBox(width: Insets.sm),
                  Pill(
                    label: '未保存',
                    color: Theme.of(context).colorScheme.tertiary,
                    dense: true,
                  ),
                ],
              ],
            ),
            actions: [
              IconButton(
                tooltip: '运行',
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => RuntimePage(state: state),
                  ),
                ),
                icon: const Icon(Icons.play_circle_outline),
              ),
              IconButton(
                tooltip: '撤销',
                onPressed: state.canUndo ? state.undo : null,
                icon: const Icon(Icons.undo),
              ),
              IconButton(
                tooltip: '重做',
                onPressed: state.canRedo ? state.redo : null,
                icon: const Icon(Icons.redo),
              ),
              IconButton(
                tooltip: '保存',
                onPressed: state.dirty && !_saving ? _save : null,
                icon: _saving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : Icon(state.dirty ? Icons.save : Icons.save_outlined),
              ),
              PopupMenuButton<String>(
                onSelected: (v) async {
                  switch (v) {
                    case 'issues':
                      await _showIssues(state.report);
                    case 'subscription':
                      await _subscription();
                    case 'saveAs':
                      await _saveAs();
                  }
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'issues', child: Text('校验详情')),
                  PopupMenuItem(value: 'subscription', child: Text('订阅…')),
                  PopupMenuItem(value: 'saveAs', child: Text('另存为…')),
                ],
              ),
            ],
            bottom: PreferredSize(
              preferredSize: const Size.fromHeight(48),
              child: Align(
                alignment: Alignment.centerLeft,
                child: TabBar(
                  isScrollable: true,
                  tabAlignment: TabAlignment.start,
                  padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
                  tabs: const [
                    Tab(
                      icon: Icon(Icons.account_tree_outlined, size: 19),
                      text: '代理',
                    ),
                    Tab(icon: Icon(Icons.rule_outlined, size: 19), text: '规则'),
                    Tab(icon: Icon(Icons.code, size: 19), text: 'YAML'),
                  ],
                ),
              ),
            ),
          ),
          body: Column(
            children: [
              _StatusBar(
                report: state.report,
                onTap: () => _showIssues(state.report),
              ),
              Expanded(
                child: TabBarView(
                  children: [
                    ProxyBoard(
                      state: state,
                      onSubscriptionSaved: _rememberSubscription,
                    ),
                    RulesTab(state: state),
                    RawYamlTab(state: state),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.report, required this.onTap});

  final ValidationReport report;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final clean = report.isClean;
    final (fg, dot, text) = clean
        ? (scheme.onSurfaceVariant, semantic.ok, '校验通过')
        : report.hasErrors
        ? (
            semantic.danger,
            semantic.danger,
            '${report.errors.length} 个错误 · ${report.warnings.length} 个警告',
          )
        : (semantic.warn, semantic.warn, '${report.warnings.length} 个警告');
    final bg = clean
        ? scheme.surface.withValues(alpha: 0.0)
        : report.hasErrors
        ? semantic.danger.withValues(alpha: 0.10)
        : semantic.warn.withValues(alpha: 0.10);

    return Material(
      color: bg,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(Insets.lg, 7, Insets.lg, 7),
              child: Row(
                children: [
                  StatusDot(color: dot, size: 6),
                  const SizedBox(width: Insets.sm),
                  Expanded(
                    child: Text(
                      text,
                      style: mono(11.5, color: fg, weight: 500),
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    size: 15,
                    color: fg.withValues(alpha: 0.7),
                  ),
                ],
              ),
            ),
            const Hairline(),
          ],
        ),
      ),
    );
  }
}

/// 「另存为」用的小对话框。
///
/// 控制器归 State 所有：早先的写法是 `await showDialog(...)` 后立刻
/// `ctrl.dispose()`，对话框还在退场动画里引用它，会撞
/// `_dependents.isEmpty` 断言（真机上红屏）。
class _NameDialog extends StatefulWidget {
  const _NameDialog({required this.initial});

  final String initial;

  @override
  State<_NameDialog> createState() => _NameDialogState();
}

class _NameDialogState extends State<_NameDialog> {
  late final TextEditingController _ctrl = TextEditingController(
    text: widget.initial,
  );

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('另存为'),
      content: TextField(
        controller: _ctrl,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: '配置名称',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.pop(context, v.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _ctrl.text.trim()),
          child: const Text('保存'),
        ),
      ],
    );
  }
}
