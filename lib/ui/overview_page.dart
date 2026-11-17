import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/model/app_settings.dart';
import '../runtime/runtime_controller.dart';
import '../state/settings_state.dart';
import 'theme.dart';
import 'widgets.dart';

/// 概览页：现在在跑什么、流量多少、当前配置是哪份，以及最常用的两个动作。
class OverviewPage extends StatefulWidget {
  const OverviewPage({
    super.key,
    required this.runtime,
    required this.settings,
    required this.activeProfile,
    required this.profileName,
    required this.profileCount,
    required this.onOpenEditor,
    required this.onPickProfile,
    required this.onRefreshProfiles,
    this.bottomInset = 0,
  });

  final RuntimeController runtime;
  final SettingsState? settings;
  final String? activeProfile;
  final String profileName;
  final int profileCount;
  final Future<void> Function() onOpenEditor;
  final Future<void> Function() onPickProfile;
  final Future<void> Function() onRefreshProfiles;
  final double bottomInset;

  @override
  State<OverviewPage> createState() => _OverviewPageState();
}

class _OverviewPageState extends State<OverviewPage> {
  final List<double> _history = <double>[];
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    widget.runtime.addListener(_onRuntime);
    _poll = Timer.periodic(const Duration(seconds: 2), (_) => _sample());
    unawaited(widget.runtime.refreshStatus());
  }

  @override
  void dispose() {
    widget.runtime.removeListener(_onRuntime);
    _poll?.cancel();
    super.dispose();
  }

  void _onRuntime() {
    if (!mounted) return;
    _sample();
    setState(() {});
  }

  void _sample() {
    if (!mounted) return;
    if (widget.runtime.phase != RuntimePhase.running) return;
    final value = (widget.runtime.down + widget.runtime.up).toDouble();
    if (value.isNaN || value < 0) return;
    setState(() {
      _history.add(value);
      if (_history.length > 48) _history.removeAt(0);
    });
  }

  bool get _running => widget.runtime.phase == RuntimePhase.running;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final runtime = widget.runtime;
    final semantic = context.semantic;
    final statusColor = switch (runtime.phase) {
      RuntimePhase.running => semantic.ok,
      RuntimePhase.starting || RuntimePhase.stopping => semantic.warn,
      RuntimePhase.error => semantic.danger,
      RuntimePhase.idle => scheme.onSurfaceVariant,
    };
    return CustomScrollView(
      slivers: [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.md,
            Insets.xl,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: MicroLabel(
                        'OVERVIEW',
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    IconButton(
                      tooltip: '刷新',
                      onPressed: () async {
                        await widget.onRefreshProfiles();
                        await runtime.refreshStatus();
                      },
                      icon: const Icon(Icons.refresh, size: 19),
                    ),
                  ],
                ),
                const SizedBox(height: Insets.sm),
                _StatusCard(
                  runtime: runtime,
                  statusColor: statusColor,
                  history: _history,
                  running: _running,
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.lg,
            Insets.xl,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _QuickControls(
              runtime: runtime,
              settings: widget.settings,
              onChanged: () => setState(() {}),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.lg,
            Insets.xl,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: _ActiveProfileCard(
              name: widget.profileName,
              fileName: widget.activeProfile,
              settings: widget.settings,
              profileCount: widget.profileCount,
              onOpenEditor: widget.onOpenEditor,
              onPickProfile: widget.onPickProfile,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.lg,
            Insets.xl,
            0,
          ),
          sliver: SliverToBoxAdapter(child: _LogCard(runtime: runtime)),
        ),
        SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
      ],
    );
  }
}

class _StatusCard extends StatelessWidget {
  const _StatusCard({
    required this.runtime,
    required this.statusColor,
    required this.history,
    required this.running,
  });

  final RuntimeController runtime;
  final Color statusColor;
  final List<double> history;
  final bool running;

  String get _phaseLabel => switch (runtime.phase) {
    RuntimePhase.idle => 'IDLE · 未运行',
    RuntimePhase.starting => 'STARTING · 启动中',
    RuntimePhase.running => 'RUNNING · 运行中',
    RuntimePhase.stopping => 'STOPPING · 停止中',
    RuntimePhase.error => 'ERROR · 出错',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return AppCard(
      accent: statusColor,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              StatusDot(color: statusColor, size: 7, pulsing: running),
              const SizedBox(width: Insets.sm),
              Text(
                _phaseLabel,
                style: mono(
                  11,
                  weight: 700,
                  color: statusColor,
                ).copyWith(letterSpacing: 0.8),
              ),
              const Spacer(),
              if (runtime.pid != null && runtime.pid! > 0)
                Text(
                  'PID ${runtime.pid}',
                  style: mono(10.5, color: scheme.onSurfaceVariant),
                ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              Expanded(
                child: StatTile(
                  label: '下载 DOWN',
                  value: rateParts(runtime.down).value,
                  unit: rateParts(runtime.down).unit,
                  color: running ? semantic.ok : scheme.onSurfaceVariant,
                ),
              ),
              Container(width: 1, height: 46, color: scheme.outlineVariant),
              Expanded(
                child: StatTile(
                  label: '上传 UP',
                  value: rateParts(runtime.up).value,
                  unit: rateParts(runtime.up).unit,
                  alignEnd: true,
                  color: scheme.onSurface,
                ),
              ),
            ],
          ),
          if (running && history.length > 1) ...[
            const SizedBox(height: Insets.sm),
            Sparkline(values: history, color: semantic.ok),
          ],
          const SizedBox(height: Insets.lg),
          if (runtime.isBusy)
            SizedBox(
              height: 46,
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: scheme.primary,
                  ),
                ),
              ),
            )
          else if (running)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => runtime.stop(),
                icon: const Icon(Icons.stop_circle_outlined, size: 19),
                label: const Text('停止内核'),
              ),
            )
          else
            AccentButton(
              label: '启动内核',
              icon: Icons.play_arrow_rounded,
              expand: true,
              onPressed: () => runtime.start(),
            ),
          if (runtime.lastError != null) ...[
            const SizedBox(height: Insets.md),
            Text(
              runtime.lastError!,
              style: TextStyle(
                fontSize: 12,
                height: 1.4,
                color: semantic.danger,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// 两个最常用的运行参数：代理模式 + 分流模式。
class _QuickControls extends StatelessWidget {
  const _QuickControls({
    required this.runtime,
    required this.settings,
    required this.onChanged,
  });

  final RuntimeController runtime;
  final SettingsState? settings;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final state = settings;
    if (state == null) {
      return AppCard(child: Text('还没有可用配置', style: hintStyle(context)));
    }
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const MicroLabel('运行模式'),
          const SizedBox(height: Insets.md),
          _Segmented<ProxyMode>(
            values: ProxyMode.values,
            selected: state.app.proxyMode,
            labelOf: (mode) => mode == ProxyMode.tun ? 'TUN' : '仅端口',
            onSelected: (mode) async {
              await state.setProxyMode(mode);
              onChanged();
            },
          ),
          const SizedBox(height: Insets.sm),
          Text(state.app.proxyMode.description, style: hintStyle(context)),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: state.app.proxyMode == ProxyMode.tun
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const SizedBox(height: Insets.md),
                      const MicroLabel('TUN 协议栈'),
                      const SizedBox(height: Insets.sm),
                      _Segmented<String>(
                        values: const ['gvisor', 'system', 'mixed'],
                        selected: state.tunStack,
                        labelOf: (stack) => stack,
                        onSelected: (stack) async {
                          await state.setTunStack(stack);
                          onChanged();
                        },
                      ),
                      const SizedBox(height: Insets.xs),
                      Text(
                        '默认 gvisor；换成其他栈可能上不了网。改动需重启内核生效。',
                        style: hintStyle(context),
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
          const SizedBox(height: Insets.lg),
          const MicroLabel('分流模式'),
          const SizedBox(height: Insets.md),
          _Segmented<String>(
            values: const ['rule', 'global', 'direct'],
            selected: state.mode,
            labelOf: (mode) => switch (mode) {
              'global' => '全局',
              'direct' => '直连',
              _ => '规则',
            },
            onSelected: (mode) async {
              await state.setMode(mode);
              if (runtime.phase == RuntimePhase.running) {
                await runtime.api.setMode(mode);
              }
              onChanged();
            },
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: state.mode == 'global'
                ? Padding(
                    padding: const EdgeInsets.only(top: Insets.md),
                    child: _GlobalExitRow(
                      runtime: runtime,
                      settings: state,
                      onChanged: onChanged,
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

/// 全局模式下的出口：显示 GLOBAL 当前选中的节点，点一下就能换。
///
/// 这里刻意不依赖内核是否在运行：选哪个出口是**配置状态**，先存进 sidecar，
/// 内核起来时再应用。否则没启动内核时点「切换」只会弹一句提示，看着像坏了。
class _GlobalExitRow extends StatelessWidget {
  const _GlobalExitRow({
    required this.runtime,
    required this.settings,
    required this.onChanged,
  });

  final RuntimeController runtime;
  final SettingsState settings;
  final VoidCallback onChanged;

  /// 内核的 `GLOBAL` 组能选的范围：内置出站 + 本配置里的所有节点和策略组。
  List<String> _candidates() {
    final doc = settings.doc;
    final names = <String>['DIRECT', 'REJECT'];
    for (final list in [
      doc.plainAt(['proxies']),
      doc.plainAt(['proxy-groups']),
    ]) {
      if (list is! List) continue;
      for (final item in list) {
        if (item is! Map) continue;
        final name = item['name'];
        if (name is String && name.isNotEmpty && !names.contains(name)) {
          names.add(name);
        }
      }
    }
    return names;
  }

  Future<void> _pick(BuildContext context) async {
    final candidates = _candidates();
    final picked = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              0,
              Insets.lg,
              Insets.sm,
            ),
            child: Text('GLOBAL 走哪个节点', style: display(16, weight: 700)),
          ),
          for (final name in candidates)
            ListTile(
              dense: true,
              title: Text(name),
              trailing: settings.globalNode == name
                  ? const Icon(Icons.check, size: 18)
                  : null,
              onTap: () => Navigator.pop(ctx, name),
            ),
        ],
      ),
    );
    if (picked == null) return;
    // 先落盘：内核没起来也要记住这个选择。
    await settings.setGlobalNode(picked);
    if (runtime.phase == RuntimePhase.running) {
      final ok = await runtime.selectNode('GLOBAL', picked);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('已保存；内核没有确认切换，可能已经退出')));
      }
    }
    onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final running = runtime.phase == RuntimePhase.running;
    final current =
        (running ? runtime.selected['GLOBAL'] : null) ?? settings.globalNode;
    return Row(
      children: [
        Expanded(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: '全局出口  ', style: hintStyle(context)),
                TextSpan(
                  text: current ?? '跟随内核默认（DIRECT）',
                  style: mono(12, color: Theme.of(context).colorScheme.primary),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        TextButton(onPressed: () => _pick(context), child: const Text('切换')),
      ],
    );
  }
}

class _ActiveProfileCard extends StatelessWidget {
  const _ActiveProfileCard({
    required this.name,
    required this.fileName,
    required this.settings,
    required this.profileCount,
    required this.onOpenEditor,
    required this.onPickProfile,
  });

  final String name;
  final String? fileName;
  final SettingsState? settings;
  final int profileCount;
  final Future<void> Function() onOpenEditor;
  final Future<void> Function() onPickProfile;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final doc = settings?.doc;
    final proxies = doc?.plainAt(['proxies']);
    final groups = doc?.plainAt(['proxy-groups']);
    final rules = doc?.plainAt(['rules']);
    final meta = <String>[
      '${proxies is List ? proxies.length : 0} 节点',
      '${groups is List ? groups.length : 0} 组',
      '${rules is List ? rules.length : 0} 规则',
    ];
    return AppCard(
      onTap: onOpenEditor,
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              borderRadius: const BorderRadius.all(Radius.circular(Insets.sm)),
            ),
            child: Icon(
              Icons.description_outlined,
              size: 21,
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
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: display(15.5, weight: 600),
                      ),
                    ),
                    const SizedBox(width: Insets.sm),
                    Pill(label: '$profileCount 份', dense: true),
                  ],
                ),
                const SizedBox(height: 3),
                MetaRow(items: meta),
              ],
            ),
          ),
          IconButton(
            tooltip: '切换运行配置',
            onPressed: onPickProfile,
            icon: const Icon(Icons.swap_horiz, size: 19),
          ),
        ],
      ),
    );
  }
}

class _LogCard extends StatelessWidget {
  const _LogCard({required this.runtime});

  final RuntimeController runtime;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final lines = runtime.logs.length > 8
        ? runtime.logs.sublist(runtime.logs.length - 8)
        : runtime.logs;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: MicroLabel('内核日志')),
              TextButton(
                onPressed: () async {
                  await runtime.loadLogs();
                  await runtime.refreshStatus();
                },
                child: const Text('刷新'),
              ),
            ],
          ),
          const SizedBox(height: Insets.sm),
          if (lines.isEmpty)
            Text(
              runtime.phase == RuntimePhase.idle ? '内核未运行，暂无日志' : '等待内核输出…',
              style: hintStyle(context),
            )
          else
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(Insets.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHigh,
                borderRadius: const BorderRadius.all(
                  Radius.circular(Insets.sm),
                ),
              ),
              child: SelectableText(
                lines.join('\n'),
                style: mono(10.5, color: semantic.ok.withValues(alpha: 0.85)),
                maxLines: 12,
              ),
            ),
          if (runtime.lastError != null)
            Padding(
              padding: const EdgeInsets.only(top: Insets.sm),
              child: Text(
                runtime.lastError!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.4,
                  color: semantic.danger,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 分段选择器（模式这类少量互斥选项）。
class _Segmented<T> extends StatelessWidget {
  const _Segmented({
    required this.values,
    required this.selected,
    required this.labelOf,
    required this.onSelected,
  });

  final List<T> values;
  final T selected;
  final String Function(T value) labelOf;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh,
        borderRadius: const BorderRadius.all(Radius.circular(Insets.sm)),
      ),
      child: Row(
        children: [
          for (final value in values)
            Expanded(
              child: GestureDetector(
                onTap: value == selected ? null : () => onSelected(value),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: value == selected
                        ? scheme.surfaceContainerHighest
                        : Colors.transparent,
                    borderRadius: const BorderRadius.all(Radius.circular(6)),
                  ),
                  child: TweenAnimationBuilder<Color?>(
                    tween: ColorTween(
                      end: value == selected
                          ? scheme.primary
                          : scheme.onSurfaceVariant,
                    ),
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutCubic,
                    builder: (context, color, _) => Text(
                      labelOf(value),
                      style: display(12.5, weight: 600, color: color),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 速率拆成「数值 + 单位」，好让 StatTile 用大号数字 + 小号单位排版。
({String value, String unit}) rateParts(int bytesPerSecond) {
  if (bytesPerSecond <= 0) return (value: '0', unit: 'B/s');
  if (bytesPerSecond < 1024) return (value: '$bytesPerSecond', unit: 'B/s');
  final kb = bytesPerSecond / 1024;
  if (kb < 1024) return (value: kb.toStringAsFixed(1), unit: 'KB/s');
  final mb = kb / 1024;
  return (value: mb.toStringAsFixed(2), unit: 'MB/s');
}
