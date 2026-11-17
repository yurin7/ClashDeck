import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/model/app_settings.dart';
import '../runtime/runtime_controller.dart';
import '../state/settings_state.dart';
import 'app_picker_page.dart';
import 'dropdown.dart';
import 'theme.dart';
import 'widgets.dart';

/// 设置页：把内核与本 App 的行为全部摊开成可开关的项。
///
/// 每条设置都是"立刻生效并落盘"——YAML 里的键写进配置（内核读的就是它），
/// 本 App 的行为写进 sidecar meta。改完正在运行的内核需要重载一次才生效，
/// 所以顶部有一个"重载配置"。
class SettingsPage extends StatefulWidget {
  const SettingsPage({
    super.key,
    required this.settings,
    required this.runtime,
    required this.lastSubscriptionUpdate,
    required this.onUpdateSubscription,
    required this.onImportText,
    required this.onImportUrl,
    required this.onOpenSubscription,
    this.activeName = '',
    this.bottomInset = 0,
  });

  final SettingsState? settings;
  final RuntimeController runtime;
  final DateTime? lastSubscriptionUpdate;
  final Future<void> Function() onUpdateSubscription;
  final Future<void> Function() onImportText;
  final Future<void> Function() onImportUrl;
  final Future<void> Function() onOpenSubscription;

  /// 当前激活的配置名，用来在标题上显示「设置 · <配置名>」。
  final String activeName;

  final double bottomInset;

  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _busy = false;
  Timer? _reloadTimer;

  SettingsState? get _s => widget.settings;

  Future<void> _run(Future<void> Function() action) async {
    setState(() => _busy = true);
    try {
      await action();
    } catch (error) {
      if (mounted) {
        showToast(context, '写入失败：$error');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// 内核在跑时，改完设置自动热重载（防抖 700ms），避免每拨一个开关都重载一次。
  void _scheduleReload() {
    if (!_running) return;
    _reloadTimer?.cancel();
    _reloadTimer = Timer(const Duration(milliseconds: 700), () async {
      if (!mounted || !_running) return;
      await widget.runtime.reloadConfig();
    });
  }

  @override
  void dispose() {
    _reloadTimer?.cancel();
    super.dispose();
  }

  bool get _running => widget.runtime.phase == RuntimePhase.running;

  /// 写设置 → 顺手安排一次热重载。
  Future<void> _apply(Future<void> Function() action) async {
    await _run(action);
    _scheduleReload();
  }

  /// 需要重启内核才生效的项（换 VPN 模式 / TUN 栈 / MTU / 分应用名单）：只提示，不热重载。
  Future<void> _applyRestart(Future<void> Function() action) async {
    await _run(action);
    if (!mounted || !_running) return;
    showToast(context, '这项改动需要重启内核才生效');
  }

  @override
  Widget build(BuildContext context) {
    final state = _s;
    final scheme = Theme.of(context).colorScheme;
    final activeName = widget.activeName.trim();
    // 标题留在滚动区外面，滚动时不会被带走。
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.xl,
            Insets.md,
            Insets.xl,
            0,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              MicroLabel('SETTINGS', color: scheme.onSurfaceVariant),
              const SizedBox(height: Insets.xs),
              Text(
                activeName.isEmpty ? '设置' : '设置 · $activeName',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: display(24, weight: 700),
              ),
            ],
          ),
        ),
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (state == null)
                SliverPadding(
                  padding: const EdgeInsets.all(Insets.xl),
                  sliver: SliverToBoxAdapter(
                    child: EmptyHint(
                      icon: Icons.tune,
                      title: '还没有可配置的档案',
                      message: '先新建或导入一份配置，设置会写进这份配置。',
                    ),
                  ),
                )
              else ...[
                if (_running)
                  SliverPadding(
                    padding: const EdgeInsets.fromLTRB(
                      Insets.xl,
                      Insets.lg,
                      Insets.xl,
                      0,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: AppCard(
                        accent: context.semantic.warn,
                        child: Row(
                          children: [
                            Icon(
                              Icons.info_outline,
                              size: 18,
                              color: context.semantic.warn,
                            ),
                            const SizedBox(width: Insets.sm),
                            const Expanded(child: Text('内核正在运行，改动需要重载后生效')),
                            TextButton(
                              onPressed: _busy
                                  ? null
                                  : () => _run(() async {
                                      await widget.runtime.reloadConfig();
                                    }),
                              child: const Text('重载'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                _section(
                  title: '运行',
                  icon: Icons.play_circle_outline,
                  children: [
                    _ChoiceRow<ProxyMode>(
                      label: '代理模式',
                      description: state.app.proxyMode.description,
                      value: state.app.proxyMode,
                      items: ProxyMode.values,
                      labelOf: (v) => v.label,
                      onChanged: (v) =>
                          _applyRestart(() => state.setProxyMode(v)),
                    ),
                    _ChoiceRow<AppRouteMode>(
                      label: '分应用代理',
                      description: state.app.routeMode == AppRouteMode.all
                          ? '所有应用走代理（排除本 App）'
                          : '已选 ${state.app.routePackages.length} 个应用',
                      value: state.app.routeMode,
                      items: AppRouteMode.values,
                      labelOf: (v) => v.label,
                      onChanged: (v) =>
                          _applyRestart(() => state.setRouteMode(v)),
                    ),
                    _ActionRow(
                      label: '选择应用',
                      description: state.app.routePackages.isEmpty
                          ? '未选择应用'
                          : '${state.app.routePackages.length} 个应用已选',
                      icon: Icons.apps_outlined,
                      enabled: state.app.routeMode != AppRouteMode.all,
                      onTap: () async {
                        final picked = await Navigator.of(context)
                            .push<List<String>>(
                              MaterialPageRoute(
                                builder: (_) => AppPickerPage(
                                  selected: state.app.routePackages,
                                  title:
                                      state.app.routeMode ==
                                          AppRouteMode.allowList
                                      ? '只有这些应用走代理'
                                      : '这些应用不走代理',
                                ),
                              ),
                            );
                        if (picked == null) return;
                        await _applyRestart(
                          () => state.setRoutePackages(picked),
                        );
                      },
                    ),
                    // 技术背景（只给维护者看）：system / mixed 栈会自己给网卡套地址再 bind，
                    // 而本项目的 TUN 是 VpnService 建好、把 fd 传来的，内核只把它当既有网卡
                    // （sing-tun: FileDescriptor != 0 时仅 os.NewFile 包装，stack_system.go /
                    // stack_mixed.go 依赖 interfaceFinder/bindInterface）。实测两个栈能启动、
                    // ip addr 有 198.18.0.1/30，但 core.log 没有任何连接、网页空白；gvisor 正常。
                    _ChoiceRow<String>(
                      label: 'TUN 协议栈',
                      description: '默认 gvisor；system / mixed 是实验项，暂时不可用',
                      value: state.tunStack,
                      items: const ['gvisor', 'system', 'mixed'],
                      labelOf: (v) => v == 'gvisor' ? v : '$v（实验）',
                      onChanged: (v) {
                        if (v != 'gvisor') {
                          showToast(
                            context,
                            '实验项：fd 模式下 system / mixed 目前无法联网，后续版本再支持',
                          );
                          return;
                        }
                        _applyRestart(() => state.setTunStack(v));
                      },
                    ),
                    _ChoiceRow<int>(
                      label: 'TUN MTU',
                      description: '默认 9000；网络异常时降到 1500 更稳',
                      value: state.tunMtu,
                      items: const [1500, 4064, 9000],
                      labelOf: (v) => '$v',
                      onChanged: (v) => _applyRestart(() => state.setTunMtu(v)),
                    ),
                  ],
                ),
                _section(
                  title: '分流',
                  icon: Icons.alt_route,
                  children: [
                    _ChoiceRow<String>(
                      label: '模式',
                      description: '规则：按 rules 走；全局：全部走代理；直连：全部直连',
                      value: state.mode,
                      items: const ['rule', 'global', 'direct'],
                      labelOf: (v) => switch (v) {
                        'global' => '全局代理',
                        'direct' => '直连',
                        _ => '规则',
                      },
                      onChanged: (v) => _run(() async {
                        await state.setMode(v);
                        if (_running) await widget.runtime.api.setMode(v);
                      }),
                    ),
                    _SwitchRow(
                      label: '允许局域网',
                      description: '同一 Wi-Fi 下的设备可以通过本机代理上网',
                      value: state.allowLan,
                      onChanged: (v) => _apply(() => state.setAllowLan(v)),
                    ),
                    _SwitchRow(
                      label: 'IPv6',
                      description: '允许内核使用 IPv6；关闭可避免部分网络下的黑洞',
                      value: state.ipv6,
                      onChanged: (v) => _apply(() => state.setIpv6(v)),
                    ),
                    _ChoiceRow<String>(
                      label: '日志级别',
                      description: 'debug 会写更多行',
                      value: state.logLevel,
                      items: const [
                        'silent',
                        'error',
                        'warning',
                        'info',
                        'debug',
                      ],
                      labelOf: (v) => v,
                      onChanged: (v) => _apply(() => state.setLogLevel(v)),
                    ),
                  ],
                ),
                _section(
                  title: 'DNS',
                  icon: Icons.dns_outlined,
                  children: [
                    _SwitchRow(
                      label: '启用 DNS',
                      description: 'TUN 模式下建议开启，否则域名解析交给系统',
                      value: state.dnsEnabled,
                      onChanged: (v) => _apply(() => state.setDnsEnabled(v)),
                    ),
                    _ChoiceRow<String>(
                      label: '增强模式',
                      description: 'fake-ip 更快；redir-host 兼容性更好',
                      value: state.dnsMode,
                      items: const ['fake-ip', 'redir-host'],
                      labelOf: (v) => v,
                      onChanged: (v) => _apply(() => state.setDnsMode(v)),
                    ),
                    _ValueRow(
                      label: 'fake-ip 范围',
                      value: state.fakeIpRange,
                      onTap: () => _editText(
                        title: 'fake-ip 范围',
                        initial: state.fakeIpRange,
                        hint: '例如 198.18.0.1/16',
                        onSaved: (v) async {
                          await state.setFakeIpRange(v);
                          _scheduleReload();
                        },
                      ),
                    ),
                    _ValueRow(
                      label: '名称服务器',
                      value: state.nameservers.isEmpty
                          ? '未设置'
                          : state.nameservers.join('  '),
                      onTap: () => _editText(
                        title: '名称服务器',
                        initial: state.nameservers.join(', '),
                        hint: '逗号分隔，例如 223.5.5.5, 119.29.29.29',
                        onSaved: (text) async {
                          final list = text
                              .split(RegExp(r'[,，\s]+'))
                              .map((e) => e.trim())
                              .where((e) => e.isNotEmpty)
                              .toList(growable: false);
                          await state.setNameservers(list);
                          _scheduleReload();
                        },
                      ),
                    ),
                  ],
                ),
                _section(
                  title: '订阅',
                  icon: Icons.rss_feed,
                  children: [
                    _ValueRow(
                      label: '订阅地址',
                      value: state.subscriptionUrl ?? '未设置',
                      onTap: widget.onOpenSubscription,
                    ),
                    _ChoiceRow<int>(
                      label: '自动更新',
                      description: '打开 App 时若已到期就刷新一次',
                      value: state.app.autoUpdateHours,
                      items: const [0, 6, 12, 24, 72],
                      labelOf: (v) => v == 0 ? '关闭' : '$v 小时',
                      onChanged: (v) => _run(() => state.setAutoUpdateHours(v)),
                    ),
                    _ValueRow(
                      label: '上次更新',
                      value: _formatTime(widget.lastSubscriptionUpdate),
                      onTap: () => _run(widget.onUpdateSubscription),
                    ),
                    _ActionRow(
                      label: '立即更新订阅',
                      description: '同名节点跳过，不覆盖你改过的节点',
                      icon: Icons.refresh,
                      onTap: () => _run(widget.onUpdateSubscription),
                    ),
                  ],
                ),
                _section(
                  title: '导入',
                  icon: Icons.file_download_outlined,
                  children: [
                    _ActionRow(
                      label: '粘贴文本导入',
                      description: 'YAML 配置 / 一行或多行 vless、vmess、hy2 链接',
                      icon: Icons.content_paste,
                      onTap: () => _run(widget.onImportText),
                    ),
                    _ActionRow(
                      label: '订阅地址导入',
                      description: '从 URL 拉取，生成一份新配置',
                      icon: Icons.link,
                      onTap: () => _run(widget.onImportUrl),
                    ),
                  ],
                ),
                _section(
                  title: '编辑器',
                  icon: Icons.edit_note,
                  children: [
                    _SwitchRow(
                      label: '自动保存',
                      description: '返回上一级时，有改动就询问是否保存',
                      value: state.autoSave,
                      onChanged: (v) => _run(() => state.setAutoSave(v)),
                    ),
                  ],
                ),
                _section(
                  title: '其它',
                  icon: Icons.more_horiz,
                  children: [
                    _SwitchRow(
                      label: '开机自启',
                      description: '记录开关；部分系统需要额外放行后台启动',
                      value: state.app.launchOnBoot,
                      onChanged: (v) => _run(() => state.setLaunchOnBoot(v)),
                    ),
                    const _ValueRow(
                      label: '内核',
                      value: 'mihomo (Meta) · 内置 57 MB arm64 / 61 MB x86_64',
                    ),
                    const _ValueRow(label: '许可', value: 'GPL-3.0'),
                  ],
                ),
              ],
              SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _section({
    required String title,
    required IconData icon,
    required List<Widget> children,
  }) {
    final scheme = Theme.of(context).colorScheme;
    return SliverPadding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, Insets.lg, Insets.xl, 0),
      sliver: SliverToBoxAdapter(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 15, color: scheme.primary),
                const SizedBox(width: Insets.sm),
                MicroLabel(title),
              ],
            ),
            const SizedBox(height: Insets.sm),
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Hairline(indent: Insets.lg),
                    children[i],
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _editText({
    required String title,
    required String initial,
    required String hint,
    required Future<void> Function(String value) onSaved,
  }) async {
    final controller = TextEditingController(text: initial);
    final result = await showAppDialog<String>(
      context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: hint),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    disposeAfterDialog(controller);
    if (result == null || result.isEmpty) return;
    await _run(() => onSaved(result));
  }

  static String _formatTime(DateTime? time) {
    if (time == null) return '从未';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${time.month}/${time.day} ${two(time.hour)}:${two(time.minute)}';
  }
}

/// 一行开关。
class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.label,
    required this.description,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final String description;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: value,
      onChanged: onChanged,
      contentPadding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.md, 0),
      title: Text(label, style: display(14, weight: 600)),
      subtitle: Text(description, style: hintStyle(context)),
    );
  }
}

/// 一行互斥选项（用下拉呈现）。
class _ChoiceRow<T> extends StatelessWidget {
  const _ChoiceRow({
    required this.label,
    required this.description,
    required this.value,
    required this.items,
    required this.labelOf,
    required this.onChanged,
  });

  final String label;
  final String description;
  final T value;
  final List<T> items;
  final String Function(T value) labelOf;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.lg,
        Insets.md,
        Insets.lg,
        Insets.md,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: display(14, weight: 600)),
                const SizedBox(height: 2),
                Text(description, style: hintStyle(context)),
              ],
            ),
          ),
          const SizedBox(width: Insets.md),
          AppDropdown<T>(
            compact: true,
            value: value,
            options: [
              for (final item in items) DropdownOption<T>(item, labelOf(item)),
            ],
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

/// 一行"值 + 点进去改"。
class _ValueRow extends StatelessWidget {
  const _ValueRow({required this.label, required this.value, this.onTap});

  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.md,
          Insets.lg,
          Insets.md,
        ),
        child: Row(
          children: [
            Text(label, style: display(14, weight: 600)),
            const Spacer(),
            Flexible(
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: mono(11.5, color: scheme.onSurfaceVariant),
              ),
            ),
            if (onTap != null) ...[
              const SizedBox(width: Insets.xs),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// 一行按钮型动作。
class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.description,
    required this.icon,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final String description;
  final IconData icon;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.45,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            Insets.lg,
            Insets.md,
            Insets.lg,
            Insets.md,
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: scheme.primary),
              const SizedBox(width: Insets.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: display(14, weight: 600)),
                    const SizedBox(height: 2),
                    Text(description, style: hintStyle(context)),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
