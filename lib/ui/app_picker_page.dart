import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:material_ui/material_ui.dart';

import '../runtime/platform_apps.dart';
import 'fields.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/selectable_tile.dart';

typedef AppListLoader = Future<List<AppEntry>> Function();
typedef AppIconLoader = Future<Map<String, Uint8List>> Function(
  List<String> packages,
);

/// 分应用代理的应用选择页：返回选中的包名列表（null 表示取消）。
///
/// 加载策略（300+ 应用也不白屏）：
/// 1. 首帧立刻出骨架，等清单和最短展示时长（默认 120ms）都到齐才切列表，
///    避免「转一下又一下子弹出」的跳变；
/// 2. 清单解析走 isolate（[PlatformApps.list]），不阻塞首帧；
/// 3. 图标按批异步补进列表，列表用 [ListView.builder] 只建可见行。
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({
    super.key,
    required this.selected,
    required this.title,
    this.appLoader,
    this.iconLoader,
    this.minimumLoad = const Duration(milliseconds: 120),
    this.iconBatchSize = 24,
  }) : assert(iconBatchSize > 0);

  final List<String> selected;
  final String title;

  /// 测试可注入的清单加载器；默认走 Android 通道。
  final AppListLoader? appLoader;

  /// 测试可注入的图标加载器；默认走 Android 通道。
  final AppIconLoader? iconLoader;

  /// 骨架的最短展示时长，避免快速返回时闪一下。
  final Duration minimumLoad;

  /// 每次过通道取多少个应用的图标。
  final int iconBatchSize;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  static const Key skeletonKey = Key('app-picker-skeleton');

  final TextEditingController _queryCtrl = TextEditingController();
  List<AppEntry> _apps = const <AppEntry>[];
  Map<String, Uint8List> _icons = const <String, Uint8List>{};
  late Set<String> _picked;
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _picked = widget.selected.toSet();
    unawaited(_bootstrap());
  }

  Future<void> _bootstrap() async {
    // 最短展示时长从进入页面开始算，和真实加载并行，谁慢等谁。
    final minimum = Future<void>.delayed(widget.minimumLoad);
    var apps = const <AppEntry>[];
    try {
      apps = await (widget.appLoader ?? PlatformApps.list)();
    } catch (_) {
      apps = const <AppEntry>[];
    }
    await minimum;
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
    if (apps.isNotEmpty) {
      unawaited(_loadIcons());
    }
  }

  Future<void> _loadIcons() async {
    final loader = widget.iconLoader ?? PlatformApps.icons;
    final missing = <String>[
      for (final app in _apps)
        if (!_icons.containsKey(app.package)) app.package,
    ];
    for (var start = 0; start < missing.length; start += widget.iconBatchSize) {
      final end = math.min(start + widget.iconBatchSize, missing.length);
      Map<String, Uint8List> batch;
      try {
        batch = await loader(missing.sublist(start, end));
      } catch (_) {
        batch = const <String, Uint8List>{};
      }
      if (!mounted) return;
      if (batch.isEmpty) continue;
      setState(() {
        _icons = <String, Uint8List>{..._icons, ...batch};
      });
    }
  }

  @override
  void dispose() {
    _queryCtrl.dispose();
    super.dispose();
  }

  void _toggle(String package, bool checked) {
    setState(() {
      if (checked) {
        _picked.remove(package);
      } else {
        _picked.add(package);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final query = _query.toLowerCase();
    final filtered = _query.isEmpty
        ? _apps
        : _apps
              .where(
                (app) =>
                    app.label.toLowerCase().contains(query) ||
                    app.package.toLowerCase().contains(query),
              )
              .toList(growable: false);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context, _picked.toList(growable: false)),
            child: const Text('完成'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              Insets.sm,
              Insets.lg,
              Insets.sm,
            ),
            child: AppSearchField(
              controller: _queryCtrl,
              hint: '搜索应用名或包名',
              onChanged: (value) => setState(() => _query = value.trim()),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              Insets.lg,
              0,
              Insets.lg,
              Insets.sm,
            ),
            child: Row(
              children: [
                Text('已选 ${_picked.length} 个', style: hintStyle(context)),
                const Spacer(),
                TextButton(
                  onPressed: () => setState(_picked.clear),
                  child: const Text('清空'),
                ),
              ],
            ),
          ),
          Expanded(child: _buildBody(scheme, filtered)),
        ],
      ),
    );
  }

  Widget _buildBody(ColorScheme scheme, List<AppEntry> filtered) {
    if (_loading) {
      return const _SkeletonList(key: skeletonKey);
    }
    if (_apps.isEmpty) {
      return EmptyHint(
        icon: Icons.apps_outlined,
        title: '拿不到应用列表',
        message: '当前平台没有分应用代理能力（只有 Android 支持）。',
      );
    }
    if (filtered.isEmpty) {
      return Center(child: Text('没有匹配「$_query」的应用', style: hintStyle(context)));
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: Insets.xl),
      itemCount: filtered.length,
      itemBuilder: (context, index) {
        final app = filtered[index];
        final checked = _picked.contains(app.package);
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.md,
            vertical: 1,
          ),
          child: SelectableTile(
            selected: checked,
            onTap: () => _toggle(app.package, checked),
            leading: _AppIcon(entry: app, bytes: _icons[app.package]),
            title: Text(
              app.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: display(14, weight: 500),
            ),
            subtitle: Text(
              app.package,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: mono(10.5, color: scheme.onSurfaceVariant),
            ),
          ),
        );
      },
    );
  }
}

/// 统一 32×32 的应用图标；没有图标字节时用首字母占位。
class _AppIcon extends StatelessWidget {
  const _AppIcon({required this.entry, this.bytes});

  final AppEntry entry;
  final Uint8List? bytes;

  static const double size = 32;
  static const double radius = 8;

  @override
  Widget build(BuildContext context) {
    final bytes = this.bytes;
    if (bytes != null && bytes.isNotEmpty) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: Image.memory(
          bytes,
          width: size,
          height: size,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.low,
          gaplessPlayback: true,
          errorBuilder: (context, error, stack) => _placeholder(context),
        ),
      );
    }
    return _placeholder(context);
  }

  Widget _placeholder(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final label = entry.label.trim();
    final letter = label.isEmpty
        ? '#'
        : String.fromCharCode(label.runes.first).toUpperCase();
    final palette = <Color>[
      scheme.primary,
      scheme.tertiary,
      scheme.secondary,
      scheme.error,
    ];
    var sum = 0;
    for (final unit in entry.package.codeUnits) {
      sum = (sum + unit) % 997;
    }
    final accent = palette[sum % palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Text(letter, style: display(13, weight: 600, color: accent)),
    );
  }
}

/// 加载骨架：静态占位，不做闪烁动画（动效预算留给真实状态切换）。
class _SkeletonList extends StatelessWidget {
  const _SkeletonList({super.key});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.surfaceContainerHigh;
    return ListView.builder(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        Insets.md,
        Insets.xs,
        Insets.md,
        Insets.xl,
      ),
      itemCount: 8,
      itemBuilder: (context, index) => Padding(
        padding: const EdgeInsets.symmetric(vertical: Insets.xs),
        child: Row(
          children: [
            _block(base, 32, 32, 8),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _block(base, 148, 12, 6),
                  const SizedBox(height: Insets.sm),
                  _block(base, 96, 9, 5),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _block(Color color, double width, double height, double radius) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}
