import 'package:material_ui/material_ui.dart';

import '../core/model/config_summary.dart';
import '../data/profile_store.dart';
import 'fields.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/profile_icon.dart';

typedef DesktopProfileInfo = ({ProfileOrigin origin, ConfigSummary summary});

enum _ProfileAction { rename, delete }

class DesktopProfiles extends StatelessWidget {
  const DesktopProfiles({
    super.key,
    required this.profiles,
    required this.info,
    required this.activeFile,
    required this.activeStatus,
    required this.switchingFile,
    required this.search,
    required this.searchFocus,
    this.onActivate,
    this.onEdit,
    this.onRename,
    this.onDelete,
    this.onCreate,
    this.onImport,
  });

  final List<StoredProfile> profiles;
  final Map<String, DesktopProfileInfo> info;
  final String? activeFile;
  final String activeStatus;
  final String? switchingFile;
  final TextEditingController search;
  final FocusNode searchFocus;
  final ValueChanged<String>? onActivate;
  final ValueChanged<StoredProfile>? onEdit;
  final ValueChanged<StoredProfile>? onRename;
  final ValueChanged<StoredProfile>? onDelete;
  final VoidCallback? onCreate;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: search,
    builder: (context, _) => _buildLibrary(context),
  );

  Widget _buildLibrary(BuildContext context) {
    final keyword = search.text.trim().toLowerCase();
    final visible = keyword.isEmpty
        ? profiles
        : profiles
              .where((profile) => profile.name.toLowerCase().contains(keyword))
              .toList(growable: false);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Insets.xl, 11, Insets.xl, Insets.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(child: Text('配置库', style: display(27, weight: 670))),
              OutlinedButton.icon(
                onPressed: onImport,
                icon: const Icon(Icons.file_download_outlined, size: 19),
                label: const Text('导入'),
              ),
              const SizedBox(width: Insets.md),
              AccentButton(
                label: '新建配置',
                icon: Icons.add,
                onPressed: onCreate,
                expand: false,
              ),
            ],
          ),
          const SizedBox(height: Insets.lg),
          Row(
            children: [
              SizedBox(
                width: 256,
                child: AppTextField(
                  controller: search,
                  focusNode: searchFocus,
                  hint: '搜索配置',
                  prefixIcon: const Icon(Icons.search, size: 17),
                  suffixIcon: search.text.isEmpty
                      ? null
                      : IconButton(
                          tooltip: '清除搜索',
                          onPressed: search.clear,
                          icon: const Icon(Icons.close, size: 17),
                        ),
                ),
              ),
              const SizedBox(width: Insets.lg),
              Expanded(
                child: Text(
                  activeStatus == '运行中' ? '选用另一份配置会重启内核' : '点击配置卡片选用，点击右侧图标编辑',
                  style: hintStyle(context),
                ),
              ),
            ],
          ),
          const SizedBox(height: Insets.xl),
          Expanded(
            child: visible.isEmpty
                ? Center(
                    child: EmptyHint(
                      icon: Icons.layers_outlined,
                      title: keyword.isEmpty ? '暂无配置' : '未找到匹配的配置',
                    ),
                  )
                : LayoutBuilder(
                    builder: (context, bounds) => GridView.builder(
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: bounds.maxWidth >= 810 ? 2 : 1,
                        mainAxisExtent: 108,
                        mainAxisSpacing: Insets.md,
                        crossAxisSpacing: Insets.md,
                      ),
                      itemCount: visible.length,
                      itemBuilder: (context, index) {
                        final profile = visible[index];
                        final active = profile.fileName == activeFile;
                        return _ProfileCard(
                          profile: profile,
                          info: info[profile.fileName],
                          active: active,
                          status: profile.fileName == switchingFile
                              ? '切换中'
                              : active
                              ? activeStatus
                              : null,
                          onActivate: active || onActivate == null
                              ? null
                              : () => onActivate!(profile.fileName),
                          onEdit: onEdit == null
                              ? null
                              : () => onEdit!(profile),
                          onRename: onRename == null
                              ? null
                              : () => onRename!(profile),
                          onDelete: onDelete == null
                              ? null
                              : () => onDelete!(profile),
                        );
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({
    required this.profile,
    required this.info,
    required this.active,
    required this.status,
    this.onActivate,
    this.onEdit,
    this.onRename,
    this.onDelete,
  });

  final StoredProfile profile;
  final DesktopProfileInfo? info;
  final bool active;
  final String? status;
  final VoidCallback? onActivate;
  final VoidCallback? onEdit;
  final VoidCallback? onRename;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final summary = info?.summary;
    final origin = info?.origin ?? ProfileOrigin.local;
    return Semantics(
      selected: active,
      child: AppCard(
        onTap: onActivate,
        borderColor: active ? colors.primary.withValues(alpha: 0.43) : null,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ProfileIcon(
              origin: origin,
              selected: active || status == '切换中',
              running: status == '运行中',
              switching: status == '切换中' || status == '启动中',
            ),
            const SizedBox(width: Insets.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    profile.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: display(17, weight: 600),
                  ),
                  const SizedBox(height: Insets.xs),
                  Text(
                    summary == null
                        ? profile.subtitle
                        : '${summary.proxies} 节点 · ${summary.groups} 组 · ${summary.rules} 规则'
                              '${summary.mode == null ? '' : ' · ${summary.mode}'}',
                    style: hintStyle(context),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: Insets.sm),
                  Row(
                    children: [
                      AnimatedSwitcher(
                        duration: Motion.of(context).fast,
                        child: status == null
                            ? const SizedBox.shrink()
                            : Padding(
                                key: ValueKey(status),
                                padding: const EdgeInsets.only(
                                  right: Insets.sm,
                                ),
                                child: Pill(
                                  label: status!,
                                  color: colors.primary,
                                  dense: true,
                                ),
                              ),
                      ),
                      if (summary != null)
                        Pill(
                          label: summary.valid ? '校验通过' : '配置异常',
                          color: summary.valid ? colors.primary : colors.error,
                          dense: true,
                        ),
                    ],
                  ),
                ],
              ),
            ),
            IconButton(
              onPressed: onEdit,
              tooltip: '编辑配置',
              icon: Icon(
                Icons.tune,
                size: 19,
                color: active ? colors.primary : colors.onSurfaceVariant,
              ),
            ),
            PopupMenuButton<_ProfileAction>(
              enabled: onRename != null || onDelete != null,
              tooltip: '配置操作',
              icon: const Icon(Icons.more_horiz, size: 19),
              onSelected: (action) {
                switch (action) {
                  case _ProfileAction.rename:
                    onRename?.call();
                  case _ProfileAction.delete:
                    onDelete?.call();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  value: _ProfileAction.rename,
                  enabled: onRename != null,
                  child: const Text('重命名'),
                ),
                PopupMenuItem(
                  value: _ProfileAction.delete,
                  enabled: onDelete != null,
                  child: const Text('删除'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
