import 'package:material_ui/material_ui.dart';

import '../runtime/runtime_controller.dart';
import '../state/editor_state.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/delay_badge.dart';
import 'widgets/runtime_status.dart';
import 'widgets/start_stop_button.dart';
import './widgets/app_ink.dart';
import './widgets/select_sheet.dart';

/// 运行页：启动/停止内核，看运行期策略组、切换节点、看日志与速度。
class RuntimePage extends StatefulWidget {
  const RuntimePage({super.key, required this.state, this.controller});

  final EditorState state;

  /// 外部传入的控制器（全局唯一那个）；为空时自己开一个，兼容旧调用。
  final RuntimeController? controller;

  @override
  State<RuntimePage> createState() => _RuntimePageState();
}

class _RuntimePageState extends State<RuntimePage> {
  late final RuntimeController _controller;

  /// 自己创建的控制器要自己释放，外部传进来的不能动。
  bool _ownsController = false;

  /// 最近若干次采样（下行字节/秒），画迷你折线用。
  final List<double> _history = <double>[];

  static const int _historyLimit = 48;

  @override
  void initState() {
    super.initState();
    _controller =
        widget.controller ??
        RuntimeController(configProvider: () => widget.state.doc);
    _ownsController = widget.controller == null;
    _controller.addListener(_sample);
    _controller.refreshStatus();
  }

  @override
  void dispose() {
    _controller.removeListener(_sample);
    if (_ownsController) _controller.dispose();
    super.dispose();
  }

  void _sample() {
    if (_controller.phase != RuntimePhase.running) return;
    _history.add(_controller.down.toDouble());
    if (_history.length > _historyLimit) _history.removeAt(0);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _controller,
      builder: (context, _) {
        final phase = _controller.phase;
        return Scaffold(
          appBar: AppBar(
            title: const Text('运行'),
            actions: [
              IconButton(
                tooltip: '重载配置',
                onPressed: phase == RuntimePhase.running
                    ? () async {
                        final ok = await _controller.reloadConfig();
                        if (!context.mounted) return;
                        _toast(ok ? '已热重载' : '热重载失败');
                      }
                    : null,
                icon: const Icon(Icons.sync),
              ),
              IconButton(
                tooltip: '刷新状态',
                onPressed: _controller.refreshStatus,
                icon: const Icon(Icons.refresh),
              ),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.xl,
            ),
            children: [
              _statusCard(phase),
              MotionSize(
                child: _controller.lastError == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: Insets.md),
                        child: _errorCard(),
                      ),
              ),
              if (!RuntimeController.supported) ...[
                const SizedBox(height: Insets.md),
                AppCard(
                  color: Theme.of(context).colorScheme.tertiaryContainer,
                  padding: const EdgeInsets.all(Insets.md),
                  child: Text(
                    '当前不是 Android 设备：可以编辑配置，但无法启动 VPN 内核。',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                    ),
                  ),
                ),
              ],
              const SizedBox(height: Insets.xl),
              SectionTitle(title: '配置', icon: Icons.description_outlined),
              _configCard(),
              MotionSize(
                child: phase == RuntimePhase.running
                    ? Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const SizedBox(height: Insets.xl),
                          SectionTitle(
                            title: '运行期策略组',
                            subtitle: '点一行切换节点，右下角可测速',
                            icon: Icons.hub_outlined,
                          ),
                          _groupsCard(),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
              const SizedBox(height: Insets.xl),
              _logsCard(),
            ],
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------- 状态卡片

  Widget _statusCard(RuntimePhase phase) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    final running = phase == RuntimePhase.running;

    return AppCard(
      // 保持状态卡结构，启停时保留内部过渡的 widget 状态。
      accent: running ? semantic.ok : Colors.transparent,
      color: running ? scheme.primary.withValues(alpha: 0.05) : null,
      padding: const EdgeInsets.all(Insets.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          RuntimeStatusHeader(phase: phase, pid: _controller.pid),
          const SizedBox(height: Insets.lg),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: StatTile(
                  label: '下载 DOWN',
                  value: running ? _formatRate(_controller.down) : '—',
                  color: running ? semantic.ok : scheme.onSurfaceVariant,
                ),
              ),
              Container(
                width: 1,
                height: 44,
                margin: const EdgeInsets.only(bottom: 4, right: Insets.md),
                color: scheme.outlineVariant,
              ),
              Expanded(
                child: StatTile(
                  label: '上传 UP',
                  value: running ? _formatRate(_controller.up) : '—',
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          RuntimeTrafficChart(
            running: running,
            values: _history,
            spacing: Insets.md,
            height: 42,
          ),
          const SizedBox(height: Insets.lg),
          StartStopButton(
            phase: phase,
            onStart: _controller.start,
            onStop: _controller.stop,
          ),
        ],
      ),
    );
  }

  Widget _errorCard() {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      color: scheme.errorContainer,
      borderColor: scheme.error.withValues(alpha: 0.4),
      padding: const EdgeInsets.all(Insets.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.error_outline, size: 20, color: scheme.onErrorContainer),
          const SizedBox(width: Insets.sm),
          Expanded(
            child: Text(
              _controller.lastError ?? '',
              style: TextStyle(color: scheme.onErrorContainer, height: 1.35),
            ),
          ),
        ],
      ),
    );
  }

  Widget _configCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final profile = widget.state.profile;
    return AppCard(
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              Icons.description_outlined,
              size: 20,
              color: scheme.primary,
            ),
          ),
          const SizedBox(width: Insets.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        widget.state.fileName ?? '未命名配置',
                        style: theme.textTheme.titleSmall,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (widget.state.dirty) ...[
                      const SizedBox(width: Insets.sm),
                      Pill(label: '未保存', color: scheme.tertiary, dense: true),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                MetaRow(
                  items: [
                    '${profile.proxies.length} 节点',
                    '${profile.groups.length} 组',
                    '${profile.rules.length} 规则',
                    profile.mode,
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------- 策略组卡片

  Widget _groupsCard() {
    final scheme = Theme.of(context).colorScheme;
    final groups =
        _controller.members.entries
            .where((entry) => entry.value.isNotEmpty)
            .toList(growable: false)
          ..sort((a, b) => a.key.compareTo(b.key));
    return AppCard(
      padding: const EdgeInsets.symmetric(vertical: Insets.sm),
      child: groups.isEmpty
          ? Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: Text('内核还没返回策略组', style: hintStyle(context)),
            )
          : Column(
              children: [
                for (final group in groups)
                  AppInkWell(
                    onTap: () => _pickNode(group.key, group.value),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: Insets.lg,
                        vertical: Insets.md,
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.tune, size: 18, color: scheme.primary),
                          const SizedBox(width: Insets.md),
                          Expanded(child: Text(group.key)),
                          Pill(
                            label: _controller.selected[group.key] ?? '—',
                            color: scheme.primary,
                            dense: true,
                          ),
                          const SizedBox(width: Insets.xs),
                          Icon(
                            Icons.chevron_right,
                            size: 18,
                            color: scheme.outline,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
    );
  }

  Future<void> _pickNode(String group, List<String> nodes) async {
    final picked = await showSelectSheet<String>(
      context,
      title: '切换到…',
      subtitle: group,
      body: (ctx) => ListView(
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        children: [for (final node in nodes) _delayTile(node)],
      ),
    );
    if (picked == null) return;
    final ok = await _controller.selectNode(group, picked);
    if (!mounted) return;
    _toast(ok ? '已切换到 $picked' : '切换失败');
  }

  Widget _delayTile(String node) {
    final scheme = Theme.of(context).colorScheme;
    final delay = _controller.delays[node];
    final hasResult = _controller.delays.containsKey(node);
    final color = !hasResult
        ? scheme.onSurfaceVariant
        : delay == null || delay > 800
        ? scheme.error
        : delay > 350
        ? scheme.tertiary
        : scheme.primary;
    final text = !hasResult
        ? '未测速'
        : formatDelay(delay, approx: _controller.delayApprox(node));
    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.sm),
      title: Text(
        node,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium,
      ),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Pill(label: text, color: color, dense: true),
          IconButton(
            tooltip: '测速',
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.speed, size: 18),
            onPressed: () async => _controller.testDelay(node),
          ),
        ],
      ),
      onTap: () => Navigator.of(context).pop(node),
    );
  }

  // ------------------------------------------------------------------ 日志卡片

  Widget _logsCard() {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = _controller.logs;
    final tail = lines.length <= 120
        ? lines
        : lines.sublist(lines.length - 120);
    return AppCard(
      padding: EdgeInsets.zero,
      child: ExpansionTile(
        shape: const Border(),
        collapsedShape: const Border(),
        leading: Icon(Icons.terminal, size: 20, color: scheme.onSurfaceVariant),
        title: Text('内核日志', style: theme.textTheme.titleSmall),
        subtitle: Text(
          lines.length > tail.length
              ? '最近 ${tail.length} 行 / 共 ${lines.length} 行'
              : '${lines.length} 行',
          style: hintStyle(context),
        ),
        childrenPadding: const EdgeInsets.fromLTRB(
          Insets.lg,
          0,
          Insets.lg,
          Insets.lg,
        ),
        children: [
          Row(
            children: [
              TextButton.icon(
                onPressed: () => _controller.loadLogs(),
                icon: const Icon(Icons.refresh, size: 18),
                label: const Text('刷新'),
              ),
              TextButton.icon(
                onPressed: () => _controller.clearLogs(),
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('清空'),
              ),
            ],
          ),
          MotionSize(
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(maxHeight: 300),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radiuses.sm),
              ),
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(Insets.md),
                child: SelectableText(
                  tail.isEmpty ? '（还没有日志）' : tail.join('\n'),
                  style: monoStyle(
                    context,
                    size: 11.5,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toast(String message) {
    showToast(context, message);
  }

  static String _formatRate(int bytesPerSecond) {
    if (bytesPerSecond <= 0) return '0 B/s';
    if (bytesPerSecond < 1024) return '$bytesPerSecond B/s';
    if (bytesPerSecond < 1024 * 1024) {
      return '${(bytesPerSecond / 1024).toStringAsFixed(1)} KB/s';
    }
    return '${(bytesPerSecond / 1024 / 1024).toStringAsFixed(1)} MB/s';
  }
}
