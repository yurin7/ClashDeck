import 'package:material_ui/material_ui.dart';

import '../runtime/platform_apps.dart';
import 'theme.dart';
import 'fields.dart';
import 'widgets.dart';

/// 分应用代理的应用选择页：返回选中的包名列表（null 表示取消）。
class AppPickerPage extends StatefulWidget {
  const AppPickerPage({super.key, required this.selected, required this.title});

  final List<String> selected;
  final String title;

  @override
  State<AppPickerPage> createState() => _AppPickerPageState();
}

class _AppPickerPageState extends State<AppPickerPage> {
  List<AppEntry> _apps = const [];
  late Set<String> _picked;
  String _query = '';
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _picked = widget.selected.toSet();
    _load();
  }

  Future<void> _load() async {
    final apps = await PlatformApps.list();
    if (!mounted) return;
    setState(() {
      _apps = apps;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final filtered = _query.isEmpty
        ? _apps
        : _apps
              .where(
                (app) =>
                    app.label.toLowerCase().contains(_query.toLowerCase()) ||
                    app.package.toLowerCase().contains(_query.toLowerCase()),
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
            child: AppTextField(
              hint: '搜索应用名或包名',
              prefixIcon: const Icon(Icons.search, size: 20),
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
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _apps.isEmpty
                ? EmptyHint(
                    icon: Icons.apps_outlined,
                    title: '拿不到应用列表',
                    message: '当前平台没有分应用代理能力（只有 Android 支持）。',
                  )
                : ListView.builder(
                    padding: const EdgeInsets.only(bottom: Insets.xl),
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final app = filtered[index];
                      final checked = _picked.contains(app.package);
                      return CheckboxListTile.adaptive(
                        value: checked,
                        onChanged: (value) {
                          setState(() {
                            if (value == true) {
                              _picked.add(app.package);
                            } else {
                              _picked.remove(app.package);
                            }
                          });
                        },
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: Insets.lg,
                        ),
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
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
