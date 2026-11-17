import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/edit/import_links.dart';
import '../core/model/config_summary.dart';
import '../core/parse/share_link.dart';
import '../core/parse/subscription.dart';
import '../core/yaml/yaml_doc.dart';
import '../data/profile_store.dart';
import '../runtime/runtime_controller.dart';
import 'editor_page.dart';
import 'theme.dart';
import 'widgets.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    this.activeFileName,
    this.onSetActive,
    this.onProfilesChanged,
    this.runtime,
    this.autoSave = true,
    this.bottomInset = 0,
  });

  /// 当前“运行用的”配置（概览页启动内核时用它）。
  final String? activeFileName;

  /// 把某份配置设为运行配置。
  final Future<void> Function(String fileName)? onSetActive;

  /// 配置列表变化（新建/导入/改名/删除）后的回调。
  final Future<void> Function()? onProfilesChanged;

  /// 全局唯一的运行控制器；传给编辑页后，配置页「点组内节点 = 切换该组出口」才生效。
  final RuntimeController? runtime;

  /// 设置里的「自动保存」：编辑页返回上一级时据此决定自动保存还是确认放弃。
  final bool autoSave;

  /// 给底部悬浮岛留出的空白。
  final double bottomInset;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  ProfileStore? _store;
  List<StoredProfile> _items = const [];
  bool _loading = true;
  String? _error;

  /// 每份配置的摘要缓存：`fileName -> ConfigSummary`。
  /// 读取失败时存 [ConfigSummary.unknown]，不影响其它卡片。
  Map<String, ConfigSummary> _summaries = const {};

  /// 每份配置的订阅地址缓存（没有订阅地址时值为 null）。
  Map<String, String?> _subscriptions = const {};

  /// 摘要是否还在读取（顶部统计在读取期间显示 `—`）。
  bool _summariesLoading = false;

  /// 摘要请求序号：连续刷新时只让最后一次结果落地。
  int _summaryRequest = 0;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    if (!_loading) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final store = await ProfileStore.open();
      final items = await store.list();
      if (!mounted) return;
      setState(() {
        _store = store;
        _items = items;
        _loading = false;
        _error = null;
      });
      await _loadSummaries();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '无法打开配置目录：$e';
        _loading = false;
      });
    }
  }

  Future<void> _refresh() async {
    final store = _store;
    if (store == null) return;
    final items = await store.list();
    if (!mounted) return;
    setState(() => _items = items);
    await _loadSummaries();
    // 通知外层（悬浮岛壳）刷新它自己的副本（概览/设置要读同一份配置）。
    await widget.onProfilesChanged?.call();
  }

  /// 批量读取每份配置的摘要与订阅地址。
  ///
  /// 单份文件读取/解析失败只把该份记为 [ConfigSummary.unknown]，
  /// 绝不向页面抛错。
  Future<void> _loadSummaries() async {
    final store = _store;
    if (store == null) return;
    final request = ++_summaryRequest;
    final items = List<StoredProfile>.of(_items);
    if (mounted) {
      setState(() => _summariesLoading = true);
    }
    final summaries = <String, ConfigSummary>{};
    final subscriptions = <String, String?>{};
    for (final item in items) {
      try {
        summaries[item.fileName] = ConfigSummary.fromText(
          await store.read(item.fileName),
        );
      } catch (_) {
        summaries[item.fileName] = ConfigSummary.unknown;
      }
      try {
        subscriptions[item.fileName] = await store.subscriptionUrl(
          item.fileName,
        );
      } catch (_) {
        subscriptions[item.fileName] = null;
      }
    }
    if (!mounted || request != _summaryRequest) return;
    setState(() {
      _summaries = summaries;
      _subscriptions = subscriptions;
      _summariesLoading = false;
    });
  }

  int get _totalNodes => _items.fold(
    0,
    (sum, item) => sum + (_summaries[item.fileName]?.proxies ?? 0),
  );

  int get _subscriptionCount => _items.where((item) {
    final url = _subscriptions[item.fileName];
    return url != null && url.isNotEmpty;
  }).length;

  String? _subscriptionOf(StoredProfile item) {
    final url = _subscriptions[item.fileName];
    return url == null || url.isEmpty ? null : url;
  }

  Future<void> _open(StoredProfile item) async {
    final store = _store;
    if (store == null) return;
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          store: store,
          fileName: item.fileName,
          initialText: null,
          displayName: item.name,
          runtime: widget.runtime,
          autoSave: widget.autoSave,
        ),
      ),
    );
    await _refresh();
  }

  Future<String?> _askName({String initial = '我的配置'}) async {
    final ctrl = TextEditingController(text: initial);
    final name = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('配置名称'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: '名称',
            helperText: '会作为文件名保存，可直接被 mihomo 读取',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    disposeAfterDialog(ctrl);
    if (name == null || name.isEmpty) return null;
    return name;
  }

  Future<void> _createBlank() async {
    final store = _store;
    if (store == null) return;
    final name = await _askName();
    if (name == null) return;
    final stored = await store.create(
      name,
      ProfileStore.starterConfig(name: name),
    );
    await _refresh();
    if (!mounted) return;
    await _open(stored);
  }

  Future<void> _import() async {
    final store = _store;
    if (store == null) return;
    final input = await showDialog<_ImportInput>(
      context: context,
      builder: (_) => const _ImportDialog(),
    );
    if (input == null || !mounted) return;
    final text = input.text.trim();
    if (text.isEmpty) return;
    final name = input.name.isEmpty ? '导入的配置' : input.name;

    if (_looksLikeUrl(text)) {
      await _importFromSubscriptionUrl(store, text, name);
      return;
    }

    try {
      final yaml = buildConfigFromText(text, name: name);
      final stored = await store.create(name, yaml);
      await _refresh();
      if (!mounted) return;
      await _open(stored);
    } on ConfigEditException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('导入失败：$e');
    }
  }

  static bool _looksLikeUrl(String text) {
    if (text.contains('\n')) return false;
    final lower = text.toLowerCase();
    return lower.startsWith('http://') || lower.startsWith('https://');
  }

  Future<void> _importFromSubscriptionUrl(
    ProfileStore store,
    String url,
    String fallbackName,
  ) async {
    _toast('正在拉取订阅…');
    try {
      final result = await fetchSubscription(url);
      final name = result.title?.trim().isNotEmpty == true
          ? result.title!.trim()
          : fallbackName;
      final yaml = _yamlFromSubscription(result, name);
      final stored = await store.create(name, yaml);
      await store.setSubscriptionUrl(stored.fileName, url);
      await _refresh();
      if (!mounted) return;
      _toast('已导入 ${result.count} 个节点');
      await _open(stored);
    } on ConfigEditException catch (e) {
      _toast(e.message);
    } catch (e) {
      _toast('订阅导入失败：$e');
    }
  }

  /// 订阅体是完整配置就整份用；否则在骨架配置上追加节点（进 PROXY 组）。
  static String _yamlFromSubscription(SubscriptionResult result, String name) {
    final whole = result.yamlConfig;
    if (whole != null) return whole;
    final doc = YamlDoc.parse(ProfileStore.starterConfig(name: name));
    final outcome = importProxies(doc, result.proxies, group: 'PROXY');
    if (outcome.isEmpty) {
      throw ConfigEditException('订阅里没有可导入的节点');
    }
    return outcome.doc.text;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _rename(StoredProfile item) async {
    final store = _store;
    if (store == null) return;
    final name = await _askName(initial: item.name);
    if (name == null) return;
    await store.rename(item.fileName, name);
    await _refresh();
  }

  Future<void> _delete(StoredProfile item) async {
    final store = _store;
    if (store == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('删除「${item.name}」？'),
        content: const Text('只删除这个 App 里的文件，不影响其它客户端的配置。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await store.delete(item.fileName);
    await _refresh();
  }

  /// 长按卡片时的操作面板（与右上角菜单同一套动作）。
  Future<void> _showItemMenu(StoredProfile item) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) {
        final scheme = Theme.of(ctx).colorScheme;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Insets.xl,
                  0,
                  Insets.xl,
                  Insets.sm,
                ),
                child: Text(
                  item.name,
                  style: Theme.of(ctx).textTheme.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (widget.onSetActive != null)
                ListTile(
                  leading: Icon(
                    item.fileName == widget.activeFileName
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    color: item.fileName == widget.activeFileName
                        ? scheme.primary
                        : null,
                  ),
                  title: Text(
                    item.fileName == widget.activeFileName
                        ? '当前运行配置'
                        : '设为运行配置',
                  ),
                  onTap: () => Navigator.pop(ctx, 'activate'),
                ),
              ListTile(
                leading: const Icon(Icons.drive_file_rename_outline),
                title: const Text('重命名'),
                onTap: () => Navigator.pop(ctx, 'rename'),
              ),
              ListTile(
                leading: Icon(Icons.delete_outline, color: scheme.error),
                title: Text('删除', style: TextStyle(color: scheme.error)),
                onTap: () => Navigator.pop(ctx, 'delete'),
              ),
              const SizedBox(height: Insets.sm),
            ],
          ),
        );
      },
    );
    if (!mounted) return;
    switch (action) {
      case 'activate':
        await widget.onSetActive?.call(item.fileName);
      case 'rename':
        await _rename(item);
      case 'delete':
        await _delete(item);
    }
  }

  void _handleMenu(StoredProfile item, String action) {
    switch (action) {
      case 'activate':
        widget.onSetActive?.call(item.fileName);
      case 'rename':
        _rename(item);
      case 'delete':
        _delete(item);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? _ErrorView(message: _error!, onRetry: _init)
            : _buildContent(context),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
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
            child: _Hero(
              profileCount: _items.length,
              nodeCount: _summariesLoading ? null : _totalNodes,
              subscriptionCount: _summariesLoading ? null : _subscriptionCount,
              onRefresh: _loading ? null : _refresh,
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
            child: Row(
              children: [
                Expanded(
                  child: AccentButton(
                    label: '新建配置',
                    icon: Icons.add,
                    onPressed: _loading ? null : _createBlank,
                  ),
                ),
                const SizedBox(width: Insets.sm),
                SizedBox(
                  width: 118,
                  child: OutlinedButton.icon(
                    onPressed: _loading ? null : _import,
                    icon: const Icon(Icons.file_download_outlined, size: 17),
                    label: const Text('导入'),
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverPadding(
          // SectionTitle 自带 4 的横向内边距，这里补到与卡片边缘（24）对齐。
          padding: const EdgeInsets.fromLTRB(
            Insets.xl - Insets.xs,
            Insets.sm,
            Insets.xl - Insets.xs,
            0,
          ),
          sliver: SliverToBoxAdapter(
            child: SectionTitle(
              title: '我的配置',
              subtitle: '点开编辑节点、策略组与规则',
              trailing: Pill(label: '${_items.length} 份', dense: true),
            ),
          ),
        ),
        if (_items.isEmpty)
          SliverToBoxAdapter(
            child: EmptyHint(
              icon: Icons.dns_outlined,
              title: '还没有配置',
              message:
                  '新建一份，或粘贴 vless:// 链接 / 订阅地址导入。\n'
                  '文件就是普通 YAML，mihomo 可直接使用。',
              action: Wrap(
                spacing: Insets.md,
                runSpacing: Insets.sm,
                alignment: WrapAlignment.center,
                children: [
                  FilledButton.icon(
                    onPressed: _createBlank,
                    icon: const Icon(Icons.add),
                    label: const Text('新建配置'),
                  ),
                  OutlinedButton.icon(
                    onPressed: _import,
                    icon: const Icon(Icons.file_download_outlined),
                    label: const Text('导入'),
                  ),
                ],
              ),
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              Insets.xl,
              0,
              Insets.xl,
              Insets.xxl,
            ),
            sliver: SliverToBoxAdapter(
              child: AppCard(
                padding: EdgeInsets.zero,
                child: Column(
                  children: [
                    for (var i = 0; i < _items.length; i++) ...[
                      if (i > 0) const Hairline(indent: Insets.lg),
                      _ProfileRow(
                        item: _items[i],
                        summary: _summaries[_items[i].fileName],
                        subscriptionUrl: _subscriptionOf(_items[i]),
                        onTap: () => _open(_items[i]),
                        onLongPress: () => _showItemMenu(_items[i]),
                        onMenuSelected: (action) =>
                            _handleMenu(_items[i], action),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        if (widget.bottomInset > 0)
          SliverToBoxAdapter(child: SizedBox(height: widget.bottomInset)),
      ],
    );
  }
}

/// 顶部：字标 + 一句话定位 + 三项统计。
class _Hero extends StatelessWidget {
  const _Hero({
    required this.profileCount,
    required this.nodeCount,
    required this.subscriptionCount,
    required this.onRefresh,
  });

  final int profileCount;

  /// null 表示摘要还在读取，统计位显示 `—`。
  final int? nodeCount;
  final int? subscriptionCount;
  final VoidCallback? onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ShaderMask(
                shaderCallback: (rect) => LinearGradient(
                  colors: [scheme.onSurface, scheme.primary],
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                ).createShader(rect),
                blendMode: BlendMode.srcIn,
                child: Text(
                  'ClashDeck',
                  style: display(
                    34,
                    weight: 700,
                    color: Colors.white,
                    letterSpacing: -1.4,
                  ),
                ),
              ),
            ),
            IconButton(
              tooltip: '刷新',
              onPressed: onRefresh,
              icon: const Icon(Icons.refresh, size: 20),
            ),
          ],
        ),
        Text(
          'YAML AS DATABASE · LOSSLESS EDIT · MIHOMO CORE',
          style: mono(10, color: scheme.onSurfaceVariant, letterSpacing: 1.5),
        ),
        const SizedBox(height: Insets.lg),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: StatTile(label: '配置', value: '$profileCount'),
            ),
            const _VDivider(),
            Expanded(
              child: StatTile(
                label: '节点',
                value: nodeCount == null ? '—' : '$nodeCount',
              ),
            ),
            const _VDivider(),
            Expanded(
              child: StatTile(
                label: '订阅',
                value: subscriptionCount == null ? '—' : '$subscriptionCount',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _VDivider extends StatelessWidget {
  const _VDivider();

  @override
  Widget build(BuildContext context) => Container(
    width: 1,
    height: 34,
    margin: const EdgeInsets.only(top: 14, left: Insets.md, right: Insets.md),
    color: Theme.of(context).colorScheme.outlineVariant,
  );
}

/// 单份配置：图标 + 名称 + 元信息 + 状态 + 更多菜单（行式，面板内用细线分隔）。
class _ProfileRow extends StatelessWidget {
  const _ProfileRow({
    required this.item,
    required this.summary,
    required this.subscriptionUrl,
    required this.onTap,
    required this.onLongPress,
    required this.onMenuSelected,
  });

  final StoredProfile item;

  /// null 表示摘要仍在读取。
  final ConfigSummary? summary;
  final String? subscriptionUrl;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final ValueChanged<String> onMenuSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final s = summary;
    final hasSubscription = subscriptionUrl != null;
    final host = hasSubscription
        ? (Uri.tryParse(subscriptionUrl!)?.host ?? '')
        : '';

    final meta = <String>[
      s == null ? '— 节点' : '${s.proxies} 节点',
      s == null ? '— 组' : '${s.groups} 组',
      s == null ? '— 规则' : '${s.rules} 规则',
      if (s?.mode != null && s!.mode!.isNotEmpty) s.mode!,
      _formatBytes(item.size),
      _formatDate(item.modified),
    ];

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          Insets.lg,
          Insets.md,
          Insets.sm,
          Insets.md,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radiuses.sm),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Icon(
                hasSubscription ? Icons.rss_feed : Icons.description_outlined,
                size: 17,
                color: hasSubscription
                    ? scheme.primary
                    : scheme.onSurfaceVariant,
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
                          item.name,
                          style: display(
                            15.5,
                            weight: 600,
                            color: scheme.onSurface,
                            letterSpacing: -0.1,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: Insets.sm),
                      if (s == null)
                        const Pill(label: '读取中', dense: true)
                      else if (s.valid)
                        Pill(label: '校验通过', color: scheme.primary, dense: true)
                      else
                        // 错误文案可能很长，而 Pill 内部 Row 不换行：缩到可用宽度内。
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Pill(
                              label: _shortError(s.error),
                              color: scheme.error,
                              dense: true,
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  MetaRow(items: meta),
                  if (host.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: Text(
                        '↳ $host',
                        style: mono(10.5, color: scheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              tooltip: '更多操作',
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.more_vert,
                size: 18,
                color: scheme.onSurfaceVariant,
              ),
              onSelected: onMenuSelected,
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'rename', child: Text('重命名')),
                PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});
  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        child: EmptyHint(
          icon: Icons.error_outline,
          title: '读取配置失败',
          message: message,
          action: FilledButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh),
            label: const Text('重试'),
          ),
        ),
      ),
    );
  }
}

/// 人类可读的文件大小，例如 `0.8 KB` / `12.3 KB` / `1.5 MB`。
String _formatBytes(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kb = bytes / 1024;
  if (kb < 1024) {
    return '${kb < 10 ? kb.toStringAsFixed(1) : kb.round()} KB';
  }
  final mb = kb / 1024;
  return '${mb.toStringAsFixed(1)} MB';
}

/// 卡片上的短时间：`MM/dd HH:mm`。
String _formatDate(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}/${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}

/// 把可能很长（甚至带换行）的 YAML 错误压成 pill 里的一行短标签。
String _shortError(String? error) {
  final raw = (error ?? '需要修复').replaceAll(RegExp(r'\s+'), ' ').trim();
  if (raw.isEmpty) return '需要修复';
  const maxChars = 20;
  return raw.length <= maxChars ? raw : '${raw.substring(0, maxChars)}…';
}

/// 把用户粘贴的内容变成一份可保存的配置文本。
///
/// * 含有以分享链接协议开头的行（`vless://…`、`ss://…`、订阅 base64 等）→ 当节点链接解析；
/// * 否则当作 YAML 配置整体导入（保留注释与未知字段）。
///
/// 注意：不能只判断"是否以 `#` 开头"——订阅文本经常带一行注释，那样会被误判成 YAML。
String buildConfigFromText(String text, {String name = '导入的配置'}) {
  final trimmed = text.trim();
  final hasLinkLine = RegExp(
    r'^[ \t]*(?:vless|vmess|trojan|ss|ssr|hysteria2|hy2|tuic|socks5?|http|https)://',
    multiLine: true,
    caseSensitive: false,
  ).hasMatch(trimmed);

  if (!hasLinkLine) {
    final doc = YamlDoc.parse(trimmed);
    if (doc.isValid) return trimmed;
    throw ConfigEditException(
      '没识别出配置或节点链接'
      '（YAML：${doc.error?.message ?? '根节点不是映射'}；'
      '支持 ${supportedSchemes.join(' / ')}）',
    );
  }

  final links = parseShareLinks(trimmed);
  if (links.isEmpty) {
    throw ConfigEditException(
      '没识别出配置或节点链接（支持 ${supportedSchemes.join(' / ')}）',
    );
  }
  var doc = YamlDoc.parse(ProfileStore.starterConfig(name: name));
  for (final proxy in links) {
    doc = ConfigOps.addProxy(doc, proxy, intoGroups: const ['PROXY']);
  }
  return doc.text;
}

/// 导入对话框的返回值。
class _ImportInput {
  const _ImportInput({required this.name, required this.text});

  final String name;
  final String text;
}

/// 「导入」对话框：名字 + 内容（YAML / 分享链接 / 订阅地址）。
///
/// 控制器归 State 所有（不要在 `await showDialog` 之后手动 dispose，
/// 对话框退场动画还在用它）。
class _ImportDialog extends StatefulWidget {
  const _ImportDialog();

  @override
  State<_ImportDialog> createState() => _ImportDialogState();
}

class _ImportDialogState extends State<_ImportDialog> {
  final _name = TextEditingController(text: '导入的配置');
  final _text = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    _text.dispose();
    super.dispose();
  }

  void _submit() {
    Navigator.pop(
      context,
      _ImportInput(name: _name.text.trim(), text: _text.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('导入配置'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(
                labelText: '配置名称',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: Insets.md),
            TextField(
              controller: _text,
              minLines: 6,
              maxLines: 12,
              style: monoStyle(context, size: 12),
              decoration: const InputDecoration(
                labelText: 'YAML 配置 / 分享链接 / 订阅地址',
                hintText: '整份 YAML，或 vless://…（可多行），或 https://… 订阅地址',
                alignLabelWithHint: true,
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('导入')),
      ],
    );
  }
}
