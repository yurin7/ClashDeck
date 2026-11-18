import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../core/edit/import_links.dart' as links;
import '../core/model/app_settings.dart';
import '../core/parse/subscription.dart';
import '../core/yaml/yaml_doc.dart';
import '../data/app_prefs.dart';
import '../data/profile_store.dart';
import '../runtime/runtime_controller.dart';
import '../state/settings_state.dart';
import 'editor_page.dart';
import 'home_page.dart';
import '../core/edit/config_ops.dart';
import 'import_dialogs.dart';
import 'overview_page.dart';
import 'settings_page.dart';
import 'sheets.dart';
import 'theme.dart';
import 'widgets.dart';
import 'navigation.dart';
import './widgets/text_input_dialog.dart';

/// 三页壳：概览 / 配置 / 设置，底部悬浮岛切换。
///
/// 这里是唯一持有 [RuntimeController] 的地方——概览页和设置页看到的必须是
/// 同一个内核实例，否则两页各起一个轮询、状态还会互相覆盖。
class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store});

  final ProfileStore store;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  static const double _islandHeight = 66;
  static const double _bottomInset = 108;

  /// 当前页（底部岛屿的高亮位置以此为准）。
  int _index = 0;

  /// 三页左右滑动的控制器。
  late final PageController _pager;

  /// 连续的小数页号：滑动过程中岛屿高亮跟着手指走。
  double _page = 0;

  /// 正在做切页动画。此时禁止触发切换配置这类重操作，避免中途换内核。
  bool _pagerBusy = false;
  AppPrefs? _prefs;
  List<StoredProfile> _profiles = const [];
  String? _activeFileName;

  /// 正在切过去的配置；非空时配置页把那一行标成「切换中」。
  String? _switchingFileName;

  SettingsState? _settings;
  late final RuntimeController _runtime;
  bool _ready = false;
  String? _error;
  DateTime? _lastSubscriptionUpdate;

  @override
  void initState() {
    super.initState();
    _runtime = RuntimeController(
      configProvider: _currentDoc,
      settingsProvider: () => _settings?.app ?? AppSettings.defaults,
    );
    _pager = PageController()..addListener(_onPagerScroll);
    unawaited(_boot());
  }

  void _onPagerScroll() {
    if (!_pager.hasClients) return;
    final page = _pager.page;
    if (page == null || (page - _page).abs() < 0.001) return;
    setState(() => _page = page);
  }

  /// 切到第 [target] 页。点底部按钮走这里，保证是"滑过去"而不是瞬跳。
  Future<void> _goTo(int target) async {
    if (target == _index) return;
    if (!_pager.hasClients) {
      setState(() {
        _index = target;
        _page = target.toDouble();
      });
      return;
    }
    _pagerBusy = true;
    try {
      await _pager.animateToPage(
        target,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutCubic,
      );
      if (mounted && _index != target) setState(() => _index = target);
    } finally {
      _pagerBusy = false;
    }
  }

  @override
  void dispose() {
    _pager.dispose();
    _runtime.dispose();
    super.dispose();
  }

  YamlDoc _currentDoc() =>
      _settings?.doc ?? YamlDoc.parse(ProfileStore.starterConfig(name: '临时配置'));

  String get _activeName {
    final fileName = _activeFileName;
    if (fileName == null) return '未选择配置';
    return _profiles
        .firstWhere(
          (item) => item.fileName == fileName,
          orElse: () => StoredProfile(
            fileName: fileName,
            size: 0,
            modified: DateTime.now(),
          ),
        )
        .name;
  }

  // ------------------------------------------------------------------ 启动

  Future<void> _boot() async {
    try {
      final prefs = await AppPrefs.load();
      _prefs = prefs;
      _lastSubscriptionUpdate = prefs.lastSubscriptionUpdate;
      await _reloadProfiles(pickActive: true);
      if (!mounted) return;
      setState(() => _ready = true);
      unawaited(_maybeAutoUpdate());
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _ready = true;
        _error = '$error';
      });
    }
  }

  Future<void> _reloadProfiles({bool pickActive = false}) async {
    final items = await widget.store.list();
    var active = _activeFileName;
    final candidates = <String?>[
      active,
      _prefs?.activeProfile,
      if (items.isNotEmpty) items.first.fileName,
    ];
    active = null;
    for (final candidate in candidates) {
      if (candidate != null && items.any((e) => e.fileName == candidate)) {
        active = candidate;
        break;
      }
    }
    SettingsState? settings;
    if (active != null) {
      settings = await SettingsState.load(widget.store, active);
    }
    if (!mounted) return;
    _settings?.removeListener(_onSettingsChanged);
    setState(() {
      _profiles = items;
      _activeFileName = active;
      _settings = settings;
    });
    settings?.addListener(_onSettingsChanged);
    if (active != null && active != _prefs?.activeProfile) {
      await _prefs?.setActiveProfile(active);
    }
    if (pickActive) return;
  }

  void _onSettingsChanged() {
    if (mounted) setState(() {});
  }

  /// 切换运行配置。
  ///
  /// 内核在跑的时候要真的把流量切过去：先停（否则旧配置的 TUN/端口还占着，
  /// 新配置起不来），换好配置再重新启动，全程对用户只表现为「停顿一下」。
  Future<void> _setActive(String fileName) async {
    // 切页动画期间别换内核：用户在本页看到的内容会和实际跑的对不上。
    if (_pagerBusy) {
      _toast('正在切换页面，稍后再试');
      return;
    }
    if (fileName == _activeFileName) return;
    final wasRunning =
        _runtime.phase == RuntimePhase.running ||
        _runtime.phase == RuntimePhase.starting;
    if (_runtime.isBusy) {
      showTopNotice(context, '已取消切换', ok: false);
      return;
    }
    final name = _profileName(fileName);
    // 切换期间列表顺序不变，只把这一行标成「切换中」；顶部胶囊说明进度。
    setState(() => _switchingFileName = fileName);
    showTopNotice(context, '正在切换到「$name」…');
    try {
      if (wasRunning) {
        await _runtime.stop();
      }
      await _prefs?.setActiveProfile(fileName);
      // 先改内存里的 active 再重载：`_reloadProfiles` 会把 `_activeFileName`
      // 当第一候选，顺序反了它就会拿旧值把偏好写回去。
      if (mounted) {
        setState(() => _activeFileName = fileName);
      }
      await _reloadProfiles();
      if (!mounted) return;
      if (!wasRunning) {
        showTopNotice(context, '✓ 已切换到「$name」');
        return;
      }
      try {
        await _runtime.start();
        if (mounted) {
          showTopNotice(context, '✓ 已切换到「$name」并重启内核');
        }
      } catch (error) {
        if (mounted) _toast('切换后启动内核失败：$error');
      }
    } finally {
      // 取消、异常、成功都要收干净，否则那一行会一直转圈。
      if (mounted) setState(() => _switchingFileName = null);
    }
  }

  /// 删除一份配置。删的是当前运行配置时按「停内核 → 切到下一份 → 再删」
  /// 的顺序处理，避免内核还指着已经不存在的文件。
  Future<void> _deleteProfile(String fileName) async {
    // 切页动画期间别换内核：用户在本页看到的内容会和实际跑的对不上。
    if (_pagerBusy) {
      _toast('正在切换页面，稍后再试');
      return;
    }
    final wasActive = fileName == _activeFileName;
    final wasRunning =
        _runtime.phase == RuntimePhase.running ||
        _runtime.phase == RuntimePhase.starting;
    if (wasActive && wasRunning) {
      if (_runtime.isBusy) {
        showTopNotice(context, '已取消切换', ok: false);
        return;
      }
      await _runtime.stop();
    }
    final name = _profileName(fileName);
    // 文件名和 sidecar meta（订阅地址等）一起删。
    await widget.store.delete(fileName);
    if (wasActive) {
      await _prefs?.setActiveProfile(null);
      if (mounted) setState(() => _activeFileName = null);
    }
    await _reloadProfiles();
    if (!mounted) return;
    if (!wasActive) {
      _toast('已删除「$name」');
      return;
    }
    final next = _activeFileName;
    if (!wasRunning || next == null) {
      _toast('已删除「$name」');
      return;
    }
    try {
      await _runtime.start();
      if (mounted) {
        _toast('已删除「$name」，内核改用「${_profileName(next)}」重启');
      }
    } catch (error) {
      if (mounted) _toast('已删除「$name」，但重启内核失败：$error');
    }
  }

  String _profileName(String fileName) {
    for (final item in _profiles) {
      if (item.fileName == fileName) return item.name;
    }
    return fileName;
  }

  Future<void> _pickProfile() async {
    if (_profiles.isEmpty) {
      _toast('还没有配置，先去「配置」页新建一份');
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      title: '运行哪份配置',
      body: (ctx) => ListView(
        shrinkWrap: true,
        children: [
          for (final item in _profiles)
            ListTile(
              leading: Icon(
                item.fileName == _activeFileName
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: item.fileName == _activeFileName
                    ? Theme.of(ctx).colorScheme.primary
                    : null,
              ),
              title: Text(item.name),
              subtitle: Text(item.subtitle, style: hintStyle(ctx)),
              onTap: () => Navigator.pop(ctx, item.fileName),
            ),
        ],
      ),
    );
    if (picked != null) await _setActive(picked);
  }

  Future<void> _openEditor() async {
    final fileName = _activeFileName;
    if (fileName == null) {
      _toast('还没有配置，先去「配置」页新建一份');
      unawaited(_goTo(1));
      return;
    }
    await Navigator.of(context).push(
      appRoute<void>(
        EditorPage(
          store: widget.store,
          fileName: fileName,
          runtime: _runtime,
          autoSave: _settings?.autoSave ?? false,
        ),
      ),
    );
    await _reloadProfiles();
  }

  // ------------------------------------------------------------------ 导入

  Future<void> _importText() async {
    final text = await _showTextImportDialog();
    if (text == null || text.trim().isEmpty) return;
    try {
      final built = buildConfigFromText(text, name: '导入的配置');
      final doc = YamlDoc.parse(built);
      if (!doc.isValid) throw ConfigEditException('生成的 YAML 不合法');
      final stored = await widget.store.create('导入的配置', built);
      await _reloadProfiles();
      _toast('已导入 ${stored.name}');
      await _openEditorFor(stored.fileName);
    } on ConfigEditException catch (error) {
      _toast(error.message);
    } catch (error) {
      _toast('导入失败：$error');
    }
  }

  Future<void> _importUrl() async {
    final input = await showSubscriptionDialog(context);
    if (input == null || input.result == null) return;
    final result = input.result!;
    try {
      final String text;
      final String name = (result.title?.trim().isNotEmpty ?? false)
          ? result.title!.trim()
          : '订阅配置';
      if (result.yamlConfig != null) {
        text = result.yamlConfig!;
      } else {
        final base = YamlDoc.parse(ProfileStore.starterConfig(name: name));
        final outcome = links.importProxies(
          base,
          result.proxies,
          group: kDefaultGroupName,
        );
        text = outcome.doc.text;
      }
      final stored = await widget.store.create(name, text);
      await widget.store.setSubscriptionUrl(stored.fileName, input.url);
      await _reloadProfiles();
      _toast('已导入 ${stored.name}（${result.count} 个节点）');
      await _openEditorFor(stored.fileName);
    } catch (error) {
      _toast('导入失败：$error');
    }
  }

  Future<void> _openEditorFor(String fileName) async {
    await Navigator.of(context).push(
      appRoute<void>(
        EditorPage(
          store: widget.store,
          fileName: fileName,
          runtime: _runtime,
          autoSave: _settings?.autoSave ?? false,
        ),
      ),
    );
    await _reloadProfiles();
  }

  Future<String?> _showTextImportDialog() {
    return showTextInputDialog(
      context,
      title: '粘贴导入',
      hint: 'YAML 配置，或一行/多行 vless、vmess、hy2 链接',
      monospace: true,
      area: true,
      confirmLabel: '导入',
    );
  }

  // ------------------------------------------------------------------ 订阅

  Future<void> _openSubscription() async {
    final url = _settings?.subscriptionUrl;
    final input = await showSubscriptionDialog(context, initialUrl: url);
    if (input == null) return;
    if (input.result == null) {
      // 只保存地址
      final fileName = _activeFileName;
      if (fileName == null) return;
      await widget.store.setSubscriptionUrl(fileName, input.url);
      await _settings?.reload();
      _toast('订阅地址已保存');
      return;
    }
    final count = await _applySubscription(input.url, input.result!);
    _toast('订阅已更新：新增 $count 个节点');
  }

  Future<int> _applySubscription(String url, SubscriptionResult result) async {
    final settings = _settings;
    final fileName = _activeFileName;
    if (settings == null || fileName == null) return 0;
    var count = result.proxies.length;
    if (result.yamlConfig != null) {
      await widget.store.write(fileName, result.yamlConfig!);
      await settings.reload();
      count = result.count;
    } else {
      count = await settings.importProxies(result.proxies, skipExisting: true);
    }
    await widget.store.setSubscriptionUrl(fileName, url);
    await settings.reload();
    await _prefs?.setLastSubscriptionUpdate(DateTime.now());
    if (mounted) {
      setState(() => _lastSubscriptionUpdate = DateTime.now());
    }
    await _reloadCoreIfRunning();
    return count;
  }

  /// 订阅/设置改动后，如果内核正在跑就用新配置热重载，不必让用户手动重载。
  Future<void> _reloadCoreIfRunning() async {
    if (_runtime.phase != RuntimePhase.running) return;
    final ok = await _runtime.reloadConfig();
    if (!mounted) return;
    _toast(ok ? '内核已热重载' : '热重载失败，可在概览页停止后重新启动');
  }

  Future<void> _updateSubscription() async {
    final url = _settings?.subscriptionUrl;
    if (url == null || url.isEmpty) {
      _toast('当前配置没有订阅地址');
      return;
    }
    try {
      final result = await fetchSubscription(url);
      final count = await _applySubscription(url, result);
      _toast('订阅已更新：新增 $count 个节点');
    } catch (error) {
      _toast('更新失败：$error');
    }
  }

  Future<void> _maybeAutoUpdate() async {
    final app = _settings?.app;
    final url = _settings?.subscriptionUrl;
    if (app == null || url == null || url.isEmpty) return;
    if (app.autoUpdateHours <= 0) return;
    final last = _lastSubscriptionUpdate;
    final due =
        last == null ||
        DateTime.now().difference(last).inHours >= app.autoUpdateHours;
    if (!due) return;
    try {
      final result = await fetchSubscription(url);
      await _applySubscription(url, result);
    } catch (_) {
      // 自动更新失败静默：用户手动刷新时才会看到错误。
    }
  }

  void _toast(String message) {
    if (!mounted) return;
    showToast(context, message);
  }

  // ------------------------------------------------------------------ 视图

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_error != null) {
      return Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(Insets.xl),
            child: EmptyHint(
              icon: Icons.error_outline,
              title: '打开配置目录失败',
              message: _error,
            ),
          ),
        ),
      );
    }
    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: PageView(
              controller: _pager,
              onPageChanged: (i) => setState(() => _index = i),
              children: [
                _KeepAlivePage(
                  child: SafeArea(
                    bottom: false,
                    child: OverviewPage(
                      runtime: _runtime,
                      settings: _settings,
                      activeProfile: _activeFileName,
                      profileName: _activeName,
                      profileCount: _profiles.length,
                      onOpenEditor: _openEditor,
                      onPickProfile: _pickProfile,
                      onRefreshProfiles: _reloadProfiles,
                      bottomInset: _bottomInset,
                    ),
                  ),
                ),
                _KeepAlivePage(
                  child: HomePage(
                    activeFileName: _activeFileName,
                    switchingFileName: _switchingFileName,
                    onSetActive: _setActive,
                    onProfilesChanged: _reloadProfiles,
                    onDeleteProfile: _deleteProfile,
                    runtime: _runtime,
                    autoSave: _settings?.autoSave ?? false,
                    bottomInset: _bottomInset,
                  ),
                ),
                _KeepAlivePage(
                  child: SafeArea(
                    bottom: false,
                    child: SettingsPage(
                      settings: _settings,
                      runtime: _runtime,
                      lastSubscriptionUpdate: _lastSubscriptionUpdate,
                      onUpdateSubscription: _updateSubscription,
                      onImportText: _importText,
                      onImportUrl: _importUrl,
                      onOpenSubscription: _openSubscription,
                      activeName: _profileName(_activeFileName ?? ''),
                      bottomInset: _bottomInset,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Positioned(
            left: Insets.xl,
            right: Insets.xl,
            bottom: Insets.lg,
            child: _FloatingIsland(
              height: _islandHeight,
              index: _index,
              page: _page,
              onChanged: (i) => unawaited(_goTo(i)),
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部悬浮岛：三个入口，选中项走主色渐变。
class _FloatingIsland extends StatelessWidget {
  const _FloatingIsland({
    required this.height,
    required this.index,
    required this.page,
    required this.onChanged,
  });

  final double height;
  final int index;

  /// 连续的小数页号（0…2），滑动过程中高亮跟着手指走。
  final double page;

  final ValueChanged<int> onChanged;

  static const _items = <({IconData icon, String label})>[
    (icon: Icons.insights_outlined, label: '概览'),
    (icon: Icons.layers_outlined, label: '配置'),
    (icon: Icons.tune, label: '设置'),
  ];

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final semantic = context.semantic;
    return Container(
      height: height,
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHigh.withValues(alpha: 0.96),
        borderRadius: const BorderRadius.all(Radius.circular(Insets.xl)),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          const gap = 6.0;
          final unit = constraints.maxWidth / _items.length;
          return Stack(
            children: [
              // 高亮胶囊：跟着手指在小数页号之间滑动。
              Positioned(
                left: unit * page + gap,
                top: gap,
                bottom: gap,
                width: unit - gap * 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: semantic.accentGradient),
                    borderRadius: const BorderRadius.all(
                      Radius.circular(Insets.md),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  for (var i = 0; i < _items.length; i++)
                    Expanded(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => onChanged(i),
                        child: _item(
                          _items[i],
                          // 1 = 完全选中，0 = 完全没选中；滑动时连续过渡。
                          (1 - (page - i).abs()).clamp(0.0, 1.0),
                          scheme,
                        ),
                      ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _item(
    ({IconData icon, String label}) item,
    double t,
    ColorScheme scheme,
  ) {
    final color = Color.lerp(scheme.onSurfaceVariant, Colors.white, t)!;
    return Padding(
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(item.icon, size: 19, color: color),
          const SizedBox(height: 2),
          Text(
            item.label,
            style: display(
              10.5,
              weight: 600,
              color: color,
            ).copyWith(letterSpacing: 0.4),
          ),
        ],
      ),
    );
  }
}

/// 让 `PageView` 里的页面在切走后保留状态（滚动位置、输入中的内容等）。
class _KeepAlivePage extends StatefulWidget {
  const _KeepAlivePage({required this.child});

  final Widget child;

  @override
  State<_KeepAlivePage> createState() => _KeepAlivePageState();
}

class _KeepAlivePageState extends State<_KeepAlivePage>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}
