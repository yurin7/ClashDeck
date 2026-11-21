import 'package:material_ui/material_ui.dart';

import '../core/model/config_summary.dart';
import '../data/profile_store.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/profile_icon.dart';

typedef DesktopProfileInfo = ({ProfileOrigin origin, ConfigSummary summary});

class DesktopProfiles extends StatelessWidget {
  const DesktopProfiles({
    super.key,
    required this.profiles,
    required this.info,
    required this.activeFile,
    required this.activeStatus,
    required this.switchingFile,
    required this.filtered,
    this.onActivate,
    this.onEdit,
    this.onCreate,
    this.onImport,
  });

  final List<StoredProfile> profiles;
  final Map<String, DesktopProfileInfo> info;
  final String? activeFile;
  final String activeStatus;
  final String? switchingFile;
  final bool filtered;
  final ValueChanged<String>? onActivate;
  final ValueChanged<StoredProfile>? onEdit;
  final VoidCallback? onCreate;
  final VoidCallback? onImport;

  @override
  Widget build(BuildContext context) {
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
          const SizedBox(height: Insets.sm),
          Align(
            alignment: Alignment.centerLeft,
            child: Text(
              activeStatus == '运行中' ? '选用另一份配置会重启内核' : '点击配置卡片选用，点击右侧图标编辑',
              style: hintStyle(context),
            ),
          ),
          const SizedBox(height: Insets.xl),
          Expanded(
            child: profiles.isEmpty
                ? Center(
                    child: EmptyHint(
                      icon: Icons.layers_outlined,
                      title: filtered ? '未找到匹配的配置' : '暂无配置',
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
                      itemCount: profiles.length,
                      itemBuilder: (context, index) {
                        final profile = profiles[index];
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
  });

  final StoredProfile profile;
  final DesktopProfileInfo? info;
  final bool active;
  final String? status;
  final VoidCallback? onActivate;
  final VoidCallback? onEdit;

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
          ],
        ),
      ),
    );
  }
}
