import 'dart:convert';
import 'dart:io' show FileSystemException;
import 'dart:math' show Random;
import 'dart:ui' show AppExitResponse;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../core/model/app_settings.dart';
import '../core/model/config_summary.dart';
import '../core/model/profile.dart';
import '../core/parse/subscription.dart';
import '../core/yaml/yaml_doc.dart';
import '../data/app_prefs.dart';
import '../data/profile_store.dart';
import '../runtime/runtime_config.dart';
import '../runtime/runtime_controller.dart';
import '../runtime/windows_connections.dart';
import '../runtime/windows_kernel.dart';
import '../state/settings_state.dart';
import 'desktop_connections.dart';
import 'desktop_overview.dart';
import 'desktop_profiles.dart';
import 'desktop_window.dart';
import 'editor_page.dart';
import 'fields.dart';
import 'home_page.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/app_ink.dart';
import 'widgets/delete_confirm.dart';
import 'widgets/profile_icon.dart';
import 'widgets/text_input_dialog.dart';

/// 桌面版常驻配置库，配置在同一窗口内切换和编辑。
class DesktopWorkspace extends StatefulWidget {
  const DesktopWorkspace({super.key, required this.store});

  final ProfileStore store;

  @override
  State<DesktopWorkspace> createState() => _DesktopWorkspaceState();
}

enum _DesktopPage { overview, profiles, connections, edit }

class _DesktopWorkspaceState extends State<DesktopWorkspace> {
  final _search = TextEditingController();
  final _searchFocus = FocusNode();
  final _connectionSearchFocus = FocusNode();
  var _editor = GlobalKey<EditorPageState>();
  late final AppLifecycleListener _lifecycle;
  late final RuntimeController _runtime;
  late final WindowsConnectionMonitor _connections;
  AppPrefs? _prefs;
  SettingsState? _activeSettings;
  static final _emptyDoc = YamlDoc.parse('proxies: []');
  Profile _activeProfile = Profile.from(_emptyDoc);
  String _appVersion = '';
  _DesktopPage _page = _DesktopPage.overview;
  List<StoredProfile> _profiles = const [];
  Map<String, DesktopProfileInfo> _profileInfo = const {};
  String? _current;
  String? _switchingFile;
  RuntimePhase _phase = RuntimePhase.idle;
  String? _error;
  bool _loading = true;
  bool _busy = false;
  bool _admin = false;

  String get _activeStatus => switch (_phase) {
    RuntimePhase.running => _runtime.isTemporaryConfig ? '测速中' : '运行中',
    RuntimePhase.starting => '启动中',
    RuntimePhase.stopping => '停止中',
    RuntimePhase.error => '启动失败',
    RuntimePhase.idle => '当前选用',
  };

  String? get _tunStack {
    final stack = _prefs?.windowsTunStack;
    return RuntimeConfig.tunStacks.contains(stack) ? stack : null;
  }

  @override
  void initState() {
    super.initState();
    final random = Random.secure();
    _runtime = RuntimeController(
      configProvider: () => _activeSettings?.doc ?? _emptyDoc,
      settingsProvider: () => _activeSettings?.app ?? AppSettings.defaults,
      windowsKernel: WindowsKernel(),
      windowsTunStackProvider: () => _tunStack,
      secret: base64UrlEncode(List.generate(24, (_) => random.nextInt(256))),
    );
    _connections = WindowsConnectionMonitor(
      _runtime,
      () => {..._activeProfile.groupNames, 'GLOBAL'},
    );
    _runtime.addListener(_onRuntimeChanged);
    _lifecycle = AppLifecycleListener(onExitRequested: _onExitRequested);
    _initialize();
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _searchFocus.dispose();
    _connectionSearchFocus.dispose();
    _search.dispose();
    _connections.dispose();
    _runtime.removeListener(_onRuntimeChanged);
    _runtime.dispose();
    _activeSettings?.dispose();
    super.dispose();
  }

  void _onRuntimeChanged() {
    if (mounted && _phase != _runtime.phase) {
      setState(() => _phase = _runtime.phase);
    }
  }

  Future<AppExitResponse> _onExitRequested() async {
    if (_busy || !await _canLeave()) return AppExitResponse.cancel;
    try {
      await _runtime.shutdownWindows();
    } catch (_) {
      // 窗口退出时由原生 Job 关闭本应用的内核。
    }
    return AppExitResponse.exit;
  }

  Future<bool> _canLeave() async =>
      await _editor.currentState?.confirmLeave() ?? true;

  Future<void> _initialize() async {
    _prefs = await AppPrefs.load(directory: widget.store.dir.parent);
    await _load();
    try {
      final elevated = await WindowsKernel.isElevated();
      if (mounted) setState(() => _admin = elevated);
    } on MissingPluginException {
      // Widget tests have no native window.
    }
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      if (mounted) setState(() => _appVersion = version);
    } catch (_) {
      // 版本信息与配置编辑独立。
    }
  }

  Future<void> _load({String? select, String? active}) async {
    try {
      final items = await widget.store.list();
      final name = active ?? _activeSettings?.fileName ?? _prefs?.activeProfile;
      final activeFile = items.any((item) => item.fileName == name)
          ? name
          : items.firstOrNull?.fileName;
      final settings = activeFile == null
          ? null
          : await SettingsState.load(widget.store, activeFile);
      final oldSettings = _activeSettings;
      if (!mounted) {
        settings?.dispose();
        return;
      }
      final wanted = select ?? _current;
      final next = items.any((item) => item.fileName == wanted)
          ? wanted
          : items.firstOrNull?.fileName;
      setState(() {
        _profiles = items;
        _activeSettings = settings;
        _activeProfile = Profile.from(settings?.doc ?? _emptyDoc);
        _loading = false;
        _error = null;
        if (next != _current) _selectFile(next);
        if (select != null) _page = _DesktopPage.edit;
      });
      oldSettings?.dispose();
      await _loadProfileInfo(items);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = '无法读取配置库：$error';
      });
    }
  }

  Future<void> _loadProfileInfo(List<StoredProfile> profiles) async {
    final info = <String, DesktopProfileInfo>{};
    for (final profile in profiles) {
      if (!mounted || !identical(_profiles, profiles)) return;
      final file = profile.fileName;
      try {
        final meta = await widget.store.readMeta(file);
        final text = await widget.store.read(file);
        info[file] = (
          origin: ProfileOrigin.fromMeta(meta),
          summary: ConfigSummary.fromText(text),
        );
      } on FileSystemException {
        // 单份配置可能已被移走。
      }
    }
    if (!mounted || !identical(_profiles, profiles)) return;
    setState(() => _profileInfo = info);
  }

  void _selectFile(String? fileName) {
    _current = fileName;
    _editor = GlobalKey<EditorPageState>();
  }

  Future<void> _withProfileAction(Future<void> Function() action) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await action();
    } on ConfigEditException catch (error) {
      _notify(error.message);
    } catch (error) {
      _notify('配置操作失败：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _open(StoredProfile profile) => _withProfileAction(() async {
    if ((_page == _DesktopPage.edit && _current == profile.fileName) ||
        !await _canLeave() ||
        !mounted) {
      return;
    }
    setState(() {
      _selectFile(profile.fileName);
      _page = _DesktopPage.edit;
    });
  });

  Future<void> _navigate(_DesktopPage page) => _withProfileAction(() async {
    if (_page == page || !await _canLeave() || !mounted) return;
    setState(() => _page = page);
  });

  Future<void> _setTunStack(String? stack) => _withProfileAction(() async {
    if (_runtime.phase == RuntimePhase.running || _runtime.isBusy) return;
    await _prefs?.setWindowsTunStack(stack);
  });

  Future<void> _requestElevation() async {
    if (_busy || _runtime.isBusy || _runtime.phase == RuntimePhase.running) {
      return;
    }
    if (await WindowsKernel.relaunchElevated()) await closeDesktopWindow();
  }

  Future<void> _selectRuntimeProfile(String fileName) =>
      _withProfileAction(() async {
        if (fileName == _activeSettings?.fileName || _runtime.isBusy) return;
        final settings = await SettingsState.load(widget.store, fileName);
        if (!mounted) {
          settings.dispose();
          return;
        }
        setState(() => _switchingFile = fileName);
        try {
          if (!settings.valid) {
            _notify('这份配置的 YAML 无法解析，请先编辑修复。');
            return;
          }
          final restart = _runtime.phase == RuntimePhase.running;
          if (restart) {
            await _runtime.stop();
            if (_runtime.phase != RuntimePhase.idle) return;
          }
          if (!mounted) return;
          final previous = _activeSettings;
          setState(() {
            _activeSettings = settings;
            _activeProfile = Profile.from(settings.doc);
          });
          previous?.dispose();
          await _prefs?.setActiveProfile(fileName);
          if (mounted && restart) await _runtime.start();
        } finally {
          if (!identical(settings, _activeSettings)) settings.dispose();
          if (mounted) setState(() => _switchingFile = null);
        }
      });

  Future<void> _create() => _withProfileAction(() async {
    final name = await _askName('我的配置');
    if (name == null || !mounted || !await _canLeave() || !mounted) return;
    final created = await widget.store.create(
      name,
      ProfileStore.starterConfig(name: name),
    );
    await _load(select: created.fileName);
  });

  Future<void> _import() => _withProfileAction(() async {
    final input = await showProfileImportDialog(context);
    if (input == null || !mounted || input.text.trim().isEmpty) return;
    final text = input.text.trim();
    var name = input.name.isEmpty ? '导入的配置' : input.name;
    final isSubscription = looksLikeSubscriptionUrl(text);
    final String yaml;
    if (isSubscription) {
      _notify('正在拉取订阅…');
      final result = await fetchSubscription(text);
      final title = result.title?.trim();
      if (title != null && title.isNotEmpty) name = title;
      yaml = profileYamlFromSubscription(result, name);
    } else {
      yaml = buildConfigFromText(text, name: name);
    }
    if (!mounted || !await _canLeave() || !mounted) return;
    final created = await widget.store.create(
      name,
      yaml,
      imported: true,
      subscriptionUrl: isSubscription ? text : null,
    );
    await _load(select: created.fileName);
    _notify('已导入「${created.name}」');
  });

  Future<void> _rename(StoredProfile profile) => _withProfileAction(() async {
    final name = await _askName(profile.name);
    if (name == null || name == profile.name || !mounted) return;
    final active = profile.fileName == _current;
    final runningProfile = profile.fileName == _activeSettings?.fileName;
    if (active && !await _canLeave()) return;
    final renamed = await widget.store.rename(profile.fileName, name);
    await _load(
      select: active ? renamed : null,
      active: runningProfile ? renamed : null,
    );
    if (runningProfile) await _prefs?.setActiveProfile(renamed);
  });

  Future<void> _delete(StoredProfile profile) => _withProfileAction(() async {
    final approved = await confirmDelete(
      context,
      title: '删除「${profile.name}」？',
      message: '配置文件、订阅设置和未保存的改动都会移除。',
    );
    if (!approved || !mounted) return;
    if (profile.fileName == _current && _editor.currentState?.saving == true) {
      _notify('正在保存，请稍后再删除。');
      return;
    }
    final runningProfile = profile.fileName == _activeSettings?.fileName;
    if (runningProfile) {
      await _runtime.stop();
      if (_runtime.pid != null) return;
    }
    await widget.store.delete(profile.fileName);
    await _load();
    if (runningProfile) {
      await _prefs?.setActiveProfile(_activeSettings?.fileName);
    }
  });

  Future<String?> _askName(String initial) async {
    final input = await showTextInputDialog(
      context,
      title: '配置名称',
      initial: initial,
      label: '名称',
      confirmLabel: '确定',
    );
    final name = input?.trim();
    return name == null || name.isEmpty ? null : name;
  }

  void _notify(String message) {
    if (mounted) showToast(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final keyword = _search.text.trim().toLowerCase();
    final visible = _profiles.where((item) {
      return item.name.toLowerCase().contains(keyword);
    }).toList();
    final selected = _profiles
        .where((item) => item.fileName == _current)
        .firstOrNull;
    final active = _profiles
        .where((item) => item.fileName == _activeSettings?.fileName)
        .firstOrNull;

    return Theme(
      data: theme.copyWith(
        visualDensity: VisualDensity.compact,
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
      ),
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.keyN, control: true):
              _create,
          const SingleActivator(LogicalKeyboardKey.keyO, control: true):
              _import,
          const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
              (_page == _DesktopPage.connections
                      ? _connectionSearchFocus
                      : _searchFocus)
                  .requestFocus(),
        },
        child: Focus(
          autofocus: true,
          child: Scaffold(
            body: LayoutBuilder(
              builder: (context, bounds) => Row(
                children: [
                  SizedBox(
                    width: bounds.maxWidth >= 1100 ? 242 : 202,
                    child: Material(
                      color: colors.surfaceContainerLow,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 13, 16, 22),
                            child: Row(
                              children: [
                                Image.asset(
                                  'assets/icon/app_icon.png',
                                  width: 29,
                                  height: 29,
                                  filterQuality: FilterQuality.low,
                                ),
                                const SizedBox(width: 10),
                                Flexible(
                                  child: Text(
                                    'ClashDeck',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: display(20, weight: 700),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(11, 0, 11, 14),
                            child: Column(
                              children: [
                                _destination(
                                  _DesktopPage.overview,
                                  Icons.space_dashboard_outlined,
                                  '概览',
                                ),
                                const SizedBox(height: Insets.xs),
                                _destination(
                                  _DesktopPage.profiles,
                                  Icons.layers_outlined,
                                  '配置',
                                ),
                                const SizedBox(height: Insets.xs),
                                _destination(
                                  _DesktopPage.connections,
                                  Icons.swap_vert_circle_outlined,
                                  '连接',
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Padding(
                                    padding: const EdgeInsets.only(left: 4),
                                    child: Text(
                                      '我的配置',
                                      style: theme.textTheme.titleSmall,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  onPressed: _busy ? null : _import,
                                  tooltip: '导入配置 (Ctrl+O)',
                                  icon: const Icon(
                                    Icons.file_download_outlined,
                                    size: 19,
                                  ),
                                ),
                                IconButton(
                                  onPressed: _busy ? null : _create,
                                  tooltip: '新建配置 (Ctrl+N)',
                                  icon: const Icon(Icons.add, size: 19),
                                ),
                              ],
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
                            child: AppTextField(
                              controller: _search,
                              focusNode: _searchFocus,
                              onChanged: (_) => setState(() {}),
                              hint: '搜索配置',
                              prefixIcon: const Icon(Icons.search, size: 17),
                            ),
                          ),
                          Expanded(
                            child: visible.isEmpty
                                ? Padding(
                                    padding: const EdgeInsets.all(18),
                                    child: Text(
                                      keyword.isEmpty ? '暂无配置' : '未找到匹配的配置',
                                      style: hintStyle(context),
                                    ),
                                  )
                                : ListView.separated(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 11,
                                    ),
                                    itemCount: visible.length,
                                    separatorBuilder: (_, _) =>
                                        const SizedBox(height: 3),
                                    itemBuilder: (context, index) {
                                      final item = visible[index];
                                      final isActive =
                                          item.fileName == active?.fileName;
                                      return _ProfileListItem(
                                        key: ValueKey(item.fileName),
                                        profile: item,
                                        selected:
                                            _page == _DesktopPage.edit &&
                                            item.fileName == _current,
                                        active: isActive,
                                        origin:
                                            _profileInfo[item.fileName]
                                                ?.origin ??
                                            ProfileOrigin.local,
                                        status: item.fileName == _switchingFile
                                            ? '切换中'
                                            : isActive
                                            ? _activeStatus
                                            : null,
                                        onOpen: _busy
                                            ? null
                                            : () => _open(item),
                                        onRename: _busy
                                            ? null
                                            : () => _rename(item),
                                        onDelete: _busy
                                            ? null
                                            : () => _delete(item),
                                      );
                                    },
                                  ),
                          ),
                          const Hairline(),
                          Padding(
                            padding: const EdgeInsets.fromLTRB(18, 13, 14, 14),
                            child: Row(
                              children: [
                                Icon(
                                  Icons.desktop_windows_outlined,
                                  size: 16,
                                  color: colors.onSurfaceVariant,
                                ),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    'Windows 预览',
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: hintStyle(context),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  VerticalDivider(width: 1, color: colors.outlineVariant),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(top: desktopCaptionHeight),
                      child: _loading
                          ? const Center(child: CircularProgressIndicator())
                          : _error != null
                          ? EmptyHint(
                              icon: Icons.error_outline,
                              title: '打开配置库失败',
                              message: _error,
                              action: TextButton(
                                onPressed: _load,
                                child: const Text('重试'),
                              ),
                            )
                          : IndexedStack(
                              index: _page.index,
                              children: [
                                DesktopOverview(
                                  runtime: _runtime,
                                  active: active,
                                  origin:
                                      _profileInfo[active?.fileName]?.origin ??
                                      ProfileOrigin.local,
                                  profile: _activeProfile,
                                  prefs: _prefs,
                                  appVersion: _appVersion,
                                  busy: _busy,
                                  visible: _page == _DesktopPage.overview,
                                  connectionCount: () async =>
                                      _connections.count,
                                  tunStack: _tunStack,
                                  admin: _admin,
                                  onTunStack: _setTunStack,
                                  onRequestElevation: _requestElevation,
                                  onOpenProfiles: () =>
                                      _navigate(_DesktopPage.profiles),
                                  onEditProfile: () {
                                    if (active != null) _open(active);
                                  },
                                ),
                                DesktopProfiles(
                                  profiles: visible,
                                  info: _profileInfo,
                                  activeFile: active?.fileName,
                                  activeStatus: _activeStatus,
                                  switchingFile: _switchingFile,
                                  filtered: keyword.isNotEmpty,
                                  onActivate:
                                      _busy ||
                                          _runtime.isBusy ||
                                          _runtime.restarting ||
                                          _runtime.isTemporaryConfig
                                      ? null
                                      : _selectRuntimeProfile,
                                  onEdit: _busy ? null : _open,
                                  onCreate: _busy ? null : _create,
                                  onImport: _busy ? null : _import,
                                ),
                                DesktopConnections(
                                  monitor: _connections,
                                  visible: _page == _DesktopPage.connections,
                                  searchFocus: _connectionSearchFocus,
                                  onOpenOverview: () =>
                                      _navigate(_DesktopPage.overview),
                                ),
                                if (_page != _DesktopPage.edit)
                                  const SizedBox.shrink()
                                else if (selected != null)
                                  EditorPage(
                                    key: _editor,
                                    store: widget.store,
                                    fileName: selected.fileName,
                                    displayName: selected.name,
                                    embedded: true,
                                    autoSave: false,
                                    runtime: _runtime,
                                    isActiveProfile:
                                        selected.fileName ==
                                        _activeSettings?.fileName,
                                    cachedDelays:
                                        _prefs?.latenciesOf(
                                          selected.fileName,
                                        ) ??
                                        const {},
                                    onSaved: _load,
                                  )
                                else
                                  Center(
                                    child: EmptyHint(
                                      icon: Icons.folder_open_outlined,
                                      title: '打开一份配置',
                                      message: '导入本地 YAML、节点分享链接或订阅地址。',
                                      action: FilledButton.icon(
                                        onPressed: _busy ? null : _import,
                                        icon: const Icon(
                                          Icons.file_open_outlined,
                                          size: 17,
                                        ),
                                        label: const Text('导入配置'),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _destination(_DesktopPage page, IconData icon, String label) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      dense: true,
      selected: _page == page,
      selectedTileColor: colors.primary.withValues(alpha: 0.13),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.xs),
      ),
      leading: Icon(icon, size: 19),
      title: Text(label),
      onTap: _busy ? null : () => _navigate(page),
    );
  }
}

class _ProfileListItem extends StatelessWidget {
  const _ProfileListItem({
    super.key,
    required this.profile,
    required this.selected,
    required this.active,
    required this.origin,
    required this.status,
    this.onOpen,
    this.onRename,
    this.onDelete,
  });

  final StoredProfile profile;
  final bool selected;
  final bool active;
  final ProfileOrigin origin;
  final String? status;
  final VoidCallback? onOpen;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(8);
    return Material(
      color: selected
          ? colors.primary.withValues(alpha: 0.13)
          : Colors.transparent,
      borderRadius: radius,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              selected: selected,
              child: AppInkWell(
                onTap: onOpen,
                borderRadius: radius,
                hoverColor: colors.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 10, 0, 10),
                  child: Row(
                    children: [
                      ProfileIcon(
                        origin: origin,
                        size: 28,
                        selected: active || status == '切换中',
                        running: status == '运行中',
                        switching: status == '切换中' || status == '启动中',
                      ),
                      const SizedBox(width: 9),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              profile.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontWeight: selected || active
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                              ),
                            ),
                            AnimatedSwitcher(
                              duration: Motion.of(context).fast,
                              child: status == null
                                  ? const SizedBox.shrink()
                                  : Align(
                                      key: ValueKey(status),
                                      alignment: Alignment.centerLeft,
                                      child: Pill(
                                        label: status!,
                                        color: colors.primary,
                                        dense: true,
                                      ),
                                    ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            enabled: onRename != null,
            tooltip: '配置操作',
            onSelected: (value) =>
                value == 'rename' ? onRename?.call() : onDelete?.call(),
            icon: const Icon(Icons.more_horiz, size: 19),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'rename', child: Text('重命名')),
              PopupMenuItem(value: 'delete', child: Text('删除')),
            ],
          ),
        ],
      ),
    );
  }
}
