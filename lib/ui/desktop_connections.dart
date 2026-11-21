import 'package:material_ui/material_ui.dart';

import '../runtime/windows_connections.dart';
import 'dropdown.dart';
import 'fields.dart';
import 'overview_page.dart' show rateParts;
import 'theme.dart';
import 'widgets.dart';
import 'widgets/app_ink.dart';
import 'widgets/edit_dialog.dart';

enum _ConnectionOrder { time, download, upload }

class DesktopConnections extends StatefulWidget {
  const DesktopConnections({
    super.key,
    required this.monitor,
    required this.visible,
    required this.searchFocus,
    required this.onOpenOverview,
    this.inspectProcess,
  });

  final WindowsConnectionMonitor monitor;
  final bool visible;
  final FocusNode searchFocus;
  final String? inspectProcess;
  final VoidCallback onOpenOverview;

  @override
  State<DesktopConnections> createState() => _DesktopConnectionsState();
}

class _DesktopConnectionsState extends State<DesktopConnections> {
  final _search = TextEditingController();
  bool _closed = false;
  String? _group;
  String? _process;
  String? _rule;
  var _order = _ConnectionOrder.time;

  WindowsConnectionMonitor get _monitor => widget.monitor;

  @override
  void initState() {
    super.initState();
    _monitor.addListener(_refresh);
    _monitor.setVisible(widget.visible);
  }

  @override
  void didUpdateWidget(covariant DesktopConnections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible) {
      _monitor.setVisible(widget.visible);
    }
    if (widget.inspectProcess != null &&
        oldWidget.inspectProcess != widget.inspectProcess) {
      _search.clear();
      _closed = false;
      _group = null;
      _rule = null;
      _process = widget.inspectProcess;
      _order = _ConnectionOrder.download;
    }
  }

  @override
  void dispose() {
    _monitor.removeListener(_refresh);
    _search.dispose();
    super.dispose();
  }

  void _refresh() {
    if (widget.visible) setState(() {});
  }

  void _resetFilters() => setState(() {
    _search.clear();
    _group = null;
    _process = null;
    _rule = null;
  });

  int _sortScore(WindowsConnection entry) => switch (_order) {
    _ConnectionOrder.time => entry.startedAt?.microsecondsSinceEpoch ?? 0,
    _ConnectionOrder.download =>
      _closed ? entry.downloaded : entry.downRate ?? -1,
    _ConnectionOrder.upload => _closed ? entry.uploaded : entry.upRate ?? -1,
  };

  Widget _sortHeader(String label, _ConnectionOrder order) {
    final selected = _order == order;
    final colors = Theme.of(context).colorScheme;
    final unit = _closed ? '流量' : '速率';
    return Tooltip(
      message: selected ? '恢复默认顺序' : '按$label$unit排序',
      child: Semantics(
        selected: selected,
        button: true,
        child: AppInkWell(
          borderRadius: BorderRadius.circular(Radiuses.xs),
          onTap: () => setState(() {
            _order = selected ? _ConnectionOrder.time : order;
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: Insets.sm),
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    label,
                    style: selected ? TextStyle(color: colors.primary) : null,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: Insets.xs),
                  Icon(Icons.arrow_downward, size: 12, color: colors.primary),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _disconnect({String? id}) async {
    if (id == null) {
      final confirm = await showAppDialog<bool>(
        context,
        width: confirmDialogWidth(context),
        builder: (context) => EditDialog(
          title: '断开全部活动连接？',
          content: const Text('当前内核的连接会立即断开。'),
          confirmLabel: '断开全部',
          danger: true,
          onConfirm: () => Navigator.pop(context, true),
        ),
      );
      if (!mounted || confirm != true) return;
    }
    try {
      await _monitor.close(id: id);
    } catch (error) {
      if (mounted) showToast(context, '断开连接失败：$error');
    }
  }

  Future<void> _details(WindowsConnection entry) => showAppDialog<void>(
    context,
    width: dialogWidthOf(context),
    builder: (context) => EditDialog(
      title: '连接详情',
      subtitle: entry.destination,
      showCancel: false,
      confirmLabel: '关闭',
      onConfirm: () => Navigator.pop(context),
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _detail(context, '来源', entry.source),
          _detail(context, '协议', entry.transport),
          _detail(
            context,
            '进程',
            entry.processPath.isEmpty ? entry.process : entry.processPath,
          ),
          _detail(context, '匹配规则', entry.rule),
          _detail(context, '链路', entry.chains.join(' → ')),
          _detail(context, '已下载', _bytes(entry.downloaded)),
          _detail(context, '已上传', _bytes(entry.uploaded)),
          _detail(
            context,
            '建立时间',
            entry.startedAt?.toLocal().toString().split('.').first ?? '',
          ),
        ],
      ),
    ),
  );

  Widget _detail(BuildContext context, String label, String value) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Insets.xs),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(width: 82, child: Text(label, style: hintStyle(context))),
        Expanded(child: SelectableText(value.isEmpty ? '—' : value)),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final history = _monitor.history;
    final all = _closed ? history.closed : history.open;
    final keyword = _search.text.trim().toLowerCase();
    final filtered =
        keyword.isNotEmpty ||
        _group != null ||
        _process != null ||
        _rule != null;
    final groups = <String, String>{};
    final processes = <String, String>{};
    final rules = <String, String>{};
    final entries = <WindowsConnection>[];
    for (final entry in all) {
      for (final group in entry.groups) {
        groups[group] = group;
      }
      processes[entry.processKey] = entry.process.isEmpty
          ? '未识别'
          : entry.process;
      rules[entry.rule] = entry.rule.isEmpty ? '无匹配规则' : entry.rule;
      if (entry.matches(
        keyword: keyword,
        group: _group,
        executable: _process,
        matchedRule: _rule,
      )) {
        entries.add(entry);
      }
    }
    if (!_closed || _order != _ConnectionOrder.time) {
      entries.sort((a, b) {
        final byScore = _sortScore(b).compareTo(_sortScore(a));
        return byScore != 0 ? byScore : a.id.compareTo(b.id);
      });
    }
    final colors = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, 11, Insets.xl, Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('连接', style: display(27, weight: 670))),
              _total(
                '下载',
                Icons.south,
                history.downloaded,
                context.semantic.ok,
              ),
              const SizedBox(width: Insets.xl),
              _total('上传', Icons.north, history.uploaded, colors.primary),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Expanded(
            child: AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(Insets.lg),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            SegmentedButton<bool>(
                              showSelectedIcon: false,
                              segments: [
                                ButtonSegment(
                                  value: false,
                                  label: Text('活动 ${history.open.length}'),
                                ),
                                ButtonSegment(
                                  value: true,
                                  label: Text('已关闭 ${history.closed.length}'),
                                ),
                              ],
                              selected: {_closed},
                              onSelectionChanged: (selection) =>
                                  setState(() => _closed = selection.single),
                            ),
                            const Spacer(),
                            if (_closed)
                              TextButton.icon(
                                onPressed: all.isEmpty
                                    ? null
                                    : _monitor.clearClosed,
                                icon: const Icon(
                                  Icons.delete_sweep_outlined,
                                  size: 17,
                                ),
                                label: const Text('清空记录'),
                              )
                            else
                              TextButton.icon(
                                onPressed: all.isEmpty || _monitor.closing
                                    ? null
                                    : _disconnect,
                                style: TextButton.styleFrom(
                                  foregroundColor: colors.error,
                                ),
                                icon: const Icon(Icons.link_off, size: 17),
                                label: const Text('断开全部'),
                              ),
                          ],
                        ),
                        const SizedBox(height: Insets.md),
                        AppTextField(
                          controller: _search,
                          focusNode: widget.searchFocus,
                          hint: '搜索主机、进程或链路',
                          prefixIcon: const Icon(Icons.search, size: 18),
                          onChanged: (_) => setState(() {}),
                          suffixIcon: filtered
                              ? IconButton(
                                  tooltip: '清除筛选',
                                  icon: const Icon(
                                    Icons.filter_alt_off_outlined,
                                    size: 18,
                                  ),
                                  onPressed: _resetFilters,
                                )
                              : null,
                        ),
                        const SizedBox(height: Insets.md),
                        Row(
                          children: [
                            _filter(
                              label: '策略组',
                              icon: Icons.account_tree_outlined,
                              items: groups,
                              value: _group,
                              onChanged: (value) =>
                                  setState(() => _group = value),
                            ),
                            const SizedBox(width: Insets.md),
                            _filter(
                              label: '进程',
                              icon: Icons.apps,
                              items: processes,
                              value: _process,
                              onChanged: (value) =>
                                  setState(() => _process = value),
                            ),
                            const SizedBox(width: Insets.md),
                            _filter(
                              label: '匹配规则',
                              icon: Icons.rule,
                              items: rules,
                              value: _rule,
                              onChanged: (value) =>
                                  setState(() => _rule = value),
                            ),
                          ],
                        ),
                        if (_monitor.stale && !_closed) ...[
                          const SizedBox(height: Insets.sm),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: Text('连接数据暂未更新', style: hintStyle(context)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: colors.surfaceContainerHigh,
                      border: Border.symmetric(
                        horizontal: BorderSide(color: colors.outlineVariant),
                      ),
                    ),
                    child: SizedBox(
                      height: 36,
                      child: DefaultTextStyle(
                        style: display(11, color: colors.onSurfaceVariant),
                        child: _ConnectionColumns(
                          destination: const Text('主机'),
                          process: const Text('进程'),
                          route: const Text('链路 / 规则'),
                          download: _sortHeader(
                            '下载',
                            _ConnectionOrder.download,
                          ),
                          upload: _sortHeader('上传', _ConnectionOrder.upload),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: EmptyHint(
                              compact: true,
                              icon: Icons.link,
                              title: filtered
                                  ? '没有匹配的连接'
                                  : _closed
                                  ? '暂无关闭记录'
                                  : _monitor.running
                                  ? '暂无活动连接'
                                  : '内核未运行',
                              action: filtered
                                  ? TextButton(
                                      onPressed: _resetFilters,
                                      child: const Text('清除筛选'),
                                    )
                                  : !_closed && !_monitor.running
                                  ? TextButton(
                                      onPressed: widget.onOpenOverview,
                                      child: const Text('返回概览'),
                                    )
                                  : null,
                            ),
                          )
                        : ListView.builder(
                            itemCount: entries.length,
                            itemExtent: 59,
                            itemBuilder: (context, index) {
                              final entry = entries[index];
                              return _ConnectionRow(
                                key: ValueKey(entry.id),
                                entry: entry,
                                live: !_closed,
                                onDetails: () => _details(entry),
                                onClose: _closed || _monitor.closing
                                    ? null
                                    : () => _disconnect(id: entry.id),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _filter({
    required String label,
    required IconData icon,
    required Map<String, String> items,
    required String? value,
    required ValueChanged<String?> onChanged,
  }) {
    if (value != null) {
      items.putIfAbsent(value, () => value.isEmpty ? '未识别' : value);
    }
    final sorted = items.entries.toList()
      ..sort((a, b) => a.value.toLowerCase().compareTo(b.value.toLowerCase()));
    return Expanded(
      child: AppDropdown<String?>(
        value: value,
        label: label,
        icon: icon,
        expand: true,
        options: [
          DropdownOption(null, '全部$label'),
          for (final item in sorted) DropdownOption(item.key, item.value),
        ],
        onChanged: onChanged,
      ),
    );
  }

  Widget _total(String label, IconData icon, int bytes, Color color) => Row(
    children: [
      Icon(icon, size: 16, color: color),
      const SizedBox(width: Insets.xs),
      Text(label, style: hintStyle(context)),
      const SizedBox(width: Insets.sm),
      Text(_bytes(bytes), style: mono(13, weight: 600)),
    ],
  );
}

class _ConnectionColumns extends StatelessWidget {
  const _ConnectionColumns({
    required this.destination,
    required this.process,
    required this.route,
    required this.download,
    required this.upload,
    this.action,
  });

  final Widget destination;
  final Widget process;
  final Widget route;
  final Widget download;
  final Widget upload;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(left: Insets.lg, right: Insets.sm),
    child: Row(
      children: [
        Expanded(flex: 26, child: destination),
        const SizedBox(width: Insets.md),
        Expanded(flex: 14, child: process),
        const SizedBox(width: Insets.md),
        Expanded(flex: 24, child: route),
        const SizedBox(width: Insets.md),
        Expanded(flex: 10, child: download),
        const SizedBox(width: Insets.sm),
        Expanded(flex: 10, child: upload),
        SizedBox(width: 36, child: action),
      ],
    ),
  );
}

class _ConnectionRow extends StatelessWidget {
  const _ConnectionRow({
    super.key,
    required this.entry,
    required this.live,
    required this.onDetails,
    this.onClose,
  });

  final WindowsConnection entry;
  final bool live;
  final VoidCallback onDetails;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppInkWell(
      onTap: onDetails,
      hoverColor: colors.primary.withValues(alpha: 0.07),
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: colors.outlineVariant)),
        ),
        child: _ConnectionColumns(
          destination: _lines(
            _line(entry.destination, monoStyle(context, size: 12)),
            _line('${entry.transport} · ${entry.source}', hintStyle(context)),
          ),
          process: _line(
            entry.process.isEmpty ? '未识别' : entry.process,
            monoStyle(context, size: 11.5),
          ),
          route: _lines(
            _line(entry.chains.join(' → '), display(12, color: colors.primary)),
            _line(entry.rule, hintStyle(context)),
          ),
          download: _traffic(
            context,
            entry.downloaded,
            entry.downRate,
            context.semantic.ok,
          ),
          upload: _traffic(
            context,
            entry.uploaded,
            entry.upRate,
            colors.primary,
          ),
          action: live
              ? IconButton(
                  tooltip: '断开连接',
                  onPressed: onClose,
                  padding: EdgeInsets.zero,
                  icon: const Icon(Icons.link_off, size: 17),
                )
              : null,
        ),
      ),
    );
  }

  Widget _traffic(BuildContext context, int bytes, int? rate, Color color) {
    final parts = rate == null ? null : rateParts(rate);
    return _lines(
      _line(_bytes(bytes), monoStyle(context, size: 11.5)),
      live
          ? _line(
              parts == null ? '—' : '${parts.value} ${parts.unit}',
              mono(10, color: color),
            )
          : null,
    );
  }

  Widget _lines(Widget first, Widget? second) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    mainAxisAlignment: MainAxisAlignment.center,
    children: [first, ?second],
  );

  Widget _line(String value, TextStyle? style) => Text(
    value.isEmpty ? '—' : value,
    style: style,
    maxLines: 1,
    overflow: TextOverflow.ellipsis,
  );
}

String _bytes(int bytes) {
  if (bytes >= 1024 * 1024 * 1024) {
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
  final parts = rateParts(bytes);
  return '${parts.value} ${parts.unit.replaceFirst('/s', '')}';
}
