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
import 'import_dialogs.dart';
import 'overview_page.dart';
import 'settings_page.dart';
import 'theme.dart';
import 'widgets.dart';

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

  int _index = 0;
  AppPrefs? _prefs;
  List<StoredProfile> _profiles = const [];
  String? _activeFileName;
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
    unawaited(_boot());
  }

  @override
  void dispose() {
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

  Future<void> _setActive(String fileName) async {
    await _prefs?.setActiveProfile(fileName);
    await _reloadProfiles();
    if (!mounted) return;
    setState(() => _activeFileName = fileName);
  }

  Future<void> _pickProfile() async {
    if (_profiles.isEmpty) {
      _toast('还没有配置，先去「配置」页新建一份');
      return;
    }
    final picked = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
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
              child: Text('运行哪份配置', style: display(16, weight: 600)),
            ),
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
            const SizedBox(height: Insets.sm),
          ],
        ),
      ),
    );
    if (picked != null) await _setActive(picked);
  }

  Future<void> _openEditor() async {
    final fileName = _activeFileName;
    if (fileName == null) {
      _toast('还没有配置，先去「配置」页新建一份');
      setState(() => _index = 1);
      return;
    }
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          store: widget.store,
          fileName: fileName,
          runtime: _runtime,
          autoSave: _settings?.autoSave ?? true,
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
    final input = await showSubscriptionDialog(context, allowSaveOnly: false);
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
          group: 'PROXY',
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
      MaterialPageRoute<void>(
        builder: (_) => EditorPage(
          store: widget.store,
          fileName: fileName,
          runtime: _runtime,
          autoSave: _settings?.autoSave ?? true,
        ),
      ),
    );
    await _reloadProfiles();
  }

  Future<String?> _showTextImportDialog() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('粘贴导入'),
        content: SizedBox(
          width: 520,
          child: TextField(
            controller: controller,
            autofocus: true,
            minLines: 6,
            maxLines: 12,
            style: mono(12),
            decoration: const InputDecoration(
              hintText: 'YAML 配置，或一行/多行 vless、vmess、hy2 链接',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('导入'),
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
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
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
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
            child: IndexedStack(
              index: _index,
              children: [
                SafeArea(
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
                HomePage(
                  activeFileName: _activeFileName,
                  onSetActive: _setActive,
                  onProfilesChanged: _reloadProfiles,
                  runtime: _runtime,
                  autoSave: _settings?.autoSave ?? true,
                  bottomInset: _bottomInset,
                ),
                SafeArea(
                  bottom: false,
                  child: SettingsPage(
                    settings: _settings,
                    runtime: _runtime,
                    lastSubscriptionUpdate: _lastSubscriptionUpdate,
                    onUpdateSubscription: _updateSubscription,
                    onImportText: _importText,
                    onImportUrl: _importUrl,
                    onOpenSubscription: _openSubscription,
                    bottomInset: _bottomInset,
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
              onChanged: (i) => setState(() => _index = i),
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
    required this.onChanged,
  });

  final double height;
  final int index;
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
      child: Row(
        children: [
          for (var i = 0; i < _items.length; i++)
            Expanded(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onChanged(i),
                child: Padding(
                  padding: const EdgeInsets.all(6),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    decoration: BoxDecoration(
                      gradient: i == index
                          ? LinearGradient(colors: semantic.accentGradient)
                          : null,
                      borderRadius: const BorderRadius.all(
                        Radius.circular(Insets.md),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          _items[i].icon,
                          size: 19,
                          color: i == index
                              ? Colors.white
                              : scheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          _items[i].label,
                          style: display(
                            10.5,
                            weight: 600,
                            color: i == index
                                ? Colors.white
                                : scheme.onSurfaceVariant,
                          ).copyWith(letterSpacing: 0.4),
                        ),
                      ],
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
