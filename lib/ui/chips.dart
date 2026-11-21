import 'package:material_ui/material_ui.dart';

import 'widgets/delay_badge.dart';

import '../core/edit/rule_labels.dart';
import '../core/model/profile.dart';
import 'motion.dart';
import 'theme.dart';
import './widgets/app_ink.dart';
import 'widgets/drag_state.dart';

/// 胶囊的统一圆角：节点、规则、组、系统策略都用它，保证一排看起来是一套。
/// 选中态前景/描边色：浅色主题下品牌紫贴在白底上对比度不够，
/// 往下压到接近正文色；深色主题保持品牌紫。
Color chipSelectionColor(ColorScheme scheme) =>
    scheme.brightness == Brightness.light
    ? Color.lerp(scheme.primary, scheme.onSurface, 0.42)!
    : scheme.primary;

const double kChipRadius = 9;

/// 拖拽节点时携带的数据。
///
/// 从「未归类节点」拖出时 [fromGroup] 为 null；放进组卡的 [DragTarget] 时
/// 需要知道来源组，才能把成员从旧组里摘掉。
class DragNodeData {
  const DragNodeData(this.node, this.fromGroup);

  final String node;
  final String? fromGroup;
}

/// 内置出站（DIRECT / REJECT / PASS…）用的小图标。
IconData builtinIcon(String name) => switch (name) {
  'DIRECT' => Icons.arrow_outward,
  'REJECT' => Icons.block,
  'REJECT-DROP' => Icons.bolt,
  'PASS' => Icons.subdirectory_arrow_right,
  _ => Icons.public,
};

/// 内置出站的颜色语义：DIRECT 绿、REJECT 红、REJECT-DROP 灰。
Color systemPolicyColor(String name, ColorScheme scheme) => switch (name) {
  'DIRECT' => scheme.tertiary,
  'REJECT' => scheme.error,
  'REJECT-DROP' => scheme.onSurfaceVariant,
  _ => scheme.tertiary,
};

/// 组类型 → 图标，用来在卡片头和组胶囊上代替文字说明。
IconData groupIcon(String type) => switch (type) {
  'select' => Icons.radio_button_checked,
  'url-test' => Icons.speed,
  'fallback' => Icons.alt_route,
  'load-balance' => Icons.shuffle,
  'relay' => Icons.link,
  _ => Icons.account_tree_outlined,
};

/// 胶囊家族：决定强调色、内边距与圆角，不允许页面自绘。
enum ChipFamily { node, rule, group, systemPolicy, name }

/// 四类胶囊的唯一配色 / 尺寸来源。
///
/// 页面只引用组件、不写 `Container` 样式；要改观感只改这里。
class ChipSpec {
  const ChipSpec({
    required this.accent,
    this.selectionAccent,
    this.padding = const EdgeInsets.fromLTRB(5, 3, 4, 3),
    this.radius = kChipRadius,
  });

  /// 家族色：类型小方块 / 图标 / 未选中时的文字用它。
  final Color accent;

  /// 选中态专用强调色，四类胶囊一律是品牌紫 `scheme.primary`。
  ///
  /// 不能拿家族色参与选中态：节点家族以前用 `onSurface`，
  /// 深色主题下接近白色，选中看起来像「白块」。
  final Color? selectionAccent;

  final EdgeInsets padding;
  final double radius;

  factory ChipSpec.of(
    BuildContext context,
    ChipFamily family, {
    String? policy,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final accent = switch (family) {
      ChipFamily.node => scheme.onSurface,
      ChipFamily.rule => scheme.secondary,
      ChipFamily.group => scheme.secondary,
      ChipFamily.name => scheme.primary,
      ChipFamily.systemPolicy => systemPolicyColor(policy ?? 'DIRECT', scheme),
    };
    final padding = switch (family) {
      ChipFamily.rule => const EdgeInsets.fromLTRB(6, 4, 4, 4),
      _ => const EdgeInsets.fromLTRB(5, 3, 4, 3),
    };
    return ChipSpec(
      accent: accent,
      selectionAccent: chipSelectionColor(scheme),
      padding: padding,
    );
  }
}

/// 胶囊外壳：统一圆角、内边距、选中描边与底色。
///
/// 四类胶囊（节点 / 规则 / 组 / 系统策略）都套它，只换里面的图标和文字，
/// 这样深色背景下它们的圆角、粗细、点按时的高亮完全一致。
class ChipShell extends StatefulWidget {
  const ChipShell({
    super.key,
    required this.child,
    this.selected = false,
    this.accent,
    this.spec,
    this.onTap,
    this.onLongPress,
    this.padding = const EdgeInsets.fromLTRB(5, 3, 4, 3),
    this.margin = EdgeInsets.zero,
  });

  final Widget child;
  final bool selected;

  /// 选中时的强调色；默认取 [spec] 或主题主色。
  final Color? accent;

  /// 统一规格；传了就以它为准（四类胶囊都走 `ChipSpec.of`）。
  final ChipSpec? spec;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry margin;

  @override
  State<ChipShell> createState() => _ChipShellState();
}

class _ChipShellState extends State<ChipShell>
    with SingleTickerProviderStateMixin {
  /// 选中瞬间 0.98 → 1 的回弹；初值 1 表示未选中时没有缩放。
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: Motion.normal.chip,
    value: 1,
  );

  @override
  void didUpdateWidget(covariant ChipShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.selected && !oldWidget.selected) {
      _pulse.duration = Motion.of(context).chip;
      _pulse.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    final scheme = Theme.of(context).colorScheme;
    final selected = widget.selected;
    // 选中态只认品牌紫；家族色只服务类型小方块和未选中文字。
    final tint = selected
        ? (widget.spec?.selectionAccent ?? chipSelectionColor(scheme))
        : (widget.spec?.accent ?? widget.accent ?? scheme.primary);
    final radius = widget.spec?.radius ?? kChipRadius;
    final pad = widget.spec?.padding ?? widget.padding;
    return ScaleTransition(
      scale: Tween<double>(
        begin: 0.98,
        end: 1,
      ).animate(CurvedAnimation(parent: _pulse, curve: motion.enter)),
      child: Padding(
        padding: widget.margin,
        child: AnimatedContainer(
          duration: motion.chip,
          curve: motion.enter,
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: selected
                ? tint.withValues(alpha: 0.16)
                : scheme.surfaceContainerHigh.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(radius),
            border: Border.all(
              color: selected ? tint : scheme.outlineVariant,
              width: selected ? 1.4 : 1,
            ),
          ),
          child: AppInkWell(
            onTap: widget.onTap,
            onLongPress: widget.onLongPress,
            child: Padding(padding: pad, child: widget.child),
          ),
        ),
      ),
    );
  }
}

/// 类型小方块：节点用协议字母，规则和系统策略用图标。
class _TypeSquare extends StatelessWidget {
  const _TypeSquare({this.label, this.icon, required this.color});

  /// 统一 18×18：四类胶囊的小方块大小一致，一排看过去才不会参差。
  static const double size = 18;

  final String? label;
  final IconData? icon;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.20)),
      ),
      child: icon != null
          ? Icon(icon, size: size * 0.66, color: color)
          : Text(
              label ?? '?',
              style: mono(size * 0.47, color: color, weight: 700),
            ),
    );
  }
}

/// 节点胶囊：左侧协议字母、节点名，组内还可带 ⋮ 和 ×。
///
/// 长按可以拖到别的组；点按在组内 = 让这个组改用该节点，在节点列表 = 打开编辑。
class NodeChip extends StatelessWidget {
  const NodeChip({
    super.key,
    required this.node,
    required this.fromGroup,
    required this.onOpen,
    required this.onMove,
    required this.onDelete,
    required this.onRemove,
    this.onMenu,
    this.onSelect,
    this.selected = false,
    this.delayText,
    this.maxNameWidth,
    this.draggable = true,
    this.dragData,
    this.dragPlaceholder,
  });

  final ProxyEntry node;
  final String? fromGroup;
  final VoidCallback onOpen;
  final VoidCallback onMove;
  final VoidCallback onDelete;

  /// 非空表示「从当前组移除」；未归类节点为 null。
  final VoidCallback? onRemove;

  /// 手机上没有右键，点这个 ⋮ 打开「编辑 / 移动 / 删除」操作表。
  final VoidCallback? onMenu;

  /// 组内胶囊：点按 = 让这个组改用该节点（不打开编辑页）。
  final VoidCallback? onSelect;

  /// 该节点是否正是所属组当前选中的那个。
  final bool selected;

  /// 延迟胶囊文本（`123 ms` / `超时`）；null 表示不显示。
  final String? delayText;

  /// 节点名最大宽度；用于链式代理等窄格子里截断长名。
  final double? maxNameWidth;

  /// 是否支持长按拖拽。
  final bool draggable;

  /// 链节使用链内换位数据，拿起和浮层共用普通节点的行为。
  final Object? dragData;

  /// 活动拖拽在布局中的目标占位。
  final Widget? dragPlaceholder;

  static String typeBadge(String type) => switch (type) {
    'vless' => 'V',
    'vmess' => 'M',
    'trojan' => 'T',
    'ss' => 'S',
    'ssr' => 'R',
    'hysteria2' || 'hy2' => 'H2',
    'tuic' => 'U',
    'wireguard' => 'WG',
    'socks5' => '5',
    'http' => 'H',
    'snell' => 'SN',
    'ssh' => 'SH',
    'anytls' => 'A',
    _ => '?',
  };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shell = ChipShell(
      spec: ChipSpec.of(context, ChipFamily.node),
      selected: selected,
      onTap: onSelect ?? onOpen,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 选中只靠紫色底 / 描边表达，不再加 ✓（四类胶囊统一）。
          _TypeSquare(label: typeBadge(node.type), color: scheme.primary),
          const SizedBox(width: 6),
          // 名字必须能收缩：延迟、⋮、× 都是固定宽，长名只能自己省略。
          Flexible(
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxWidth: maxNameWidth ?? double.infinity,
              ),
              child: Text(
                node.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: display(
                  13,
                  weight: selected ? 600 : 500,
                  color: selected ? chipSelectionColor(scheme) : null,
                ),
              ),
            ),
          ),
          if (delayText != null) ...[
            const SizedBox(width: 6),
            DelayBadge(text: delayText!),
          ],
          if (onMenu != null)
            _ChipAction(icon: Icons.more_vert, tooltip: '节点操作', onTap: onMenu),
          if (onRemove != null)
            _ChipAction(
              icon: Icons.close,
              tooltip: '从组里移除',
              onTap: onRemove,
              padded: 4,
            )
          else if (onMenu == null)
            const SizedBox(width: 4),
        ],
      ),
    );

    if (!draggable) return shell;

    return ListenableBuilder(
      listenable: dragState,
      builder: (context, _) => LongPressDraggable<Object>(
        data: dragData ?? DragNodeData(node.name, fromGroup),
        // 回弹动画期间不允许再起拖，避免两层浮层叠在一起。
        maxSimultaneousDrags: dragState.animating ? 0 : null,
        // 300ms 比默认 500ms 更容易触发；长按后跟手拖动不会被滚动抢走。
        delay: const Duration(milliseconds: 300),
        hapticFeedbackOnStart: true,
        dragAnchorStrategy: childDragAnchorStrategy,
        onDragStarted: () {
          final box = context.findRenderObject() as RenderBox?;
          if (box == null || !box.hasSize) return;
          dragState.begin(
            node: node.name,
            group: fromGroup,
            sourceRect: box.localToGlobal(Offset.zero) & box.size,
            feedbackSize: box.size,
          );
        },
        onDragEnd: (details) => dragState.end(details.offset),
        feedback: Material(
          color: Colors.transparent,
          child: Opacity(
            opacity: 0.92,
            child: ListenableBuilder(
              listenable: dragState,
              builder: (context, child) => Stack(
                clipBehavior: Clip.none,
                children: [
                  ?child,
                  if (dragState.blocked)
                    Positioned(
                      right: -6,
                      top: -6,
                      child: Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          color: scheme.error,
                          shape: BoxShape.circle,
                          border: Border.all(color: scheme.surface, width: 2),
                        ),
                        child: Icon(
                          Icons.block,
                          size: 10,
                          color: scheme.onError,
                        ),
                      ),
                    ),
                ],
              ),
              child: shell,
            ),
          ),
        ),
        childWhenDragging:
            dragPlaceholder ?? Opacity(opacity: 0.3, child: shell),
        child: GestureDetector(
          onSecondaryTapDown: (details) async {
            final choice = await showMenu<String>(
              context: context,
              position: RelativeRect.fromLTRB(
                details.globalPosition.dx,
                details.globalPosition.dy,
                details.globalPosition.dx,
                details.globalPosition.dy,
              ),
              items: const [
                PopupMenuItem(value: 'edit', child: Text('编辑节点')),
                PopupMenuItem(value: 'move', child: Text('移动到…')),
                PopupMenuItem(value: 'delete', child: Text('删除节点')),
              ],
            );
            switch (choice) {
              case 'edit':
                onOpen();
              case 'move':
                onMove();
              case 'delete':
                onDelete();
            }
          },
          child: Tooltip(
            message: onSelect != null
                ? '点按 = 让「$fromGroup」改用这个节点\n⋮ 打开操作；长按可拖到别的组'
                : '${node.type} · ${node.subtitle}\n点按编辑，长按可拖到别的组',
            // 关键：默认 triggerMode 是 longPress，会和 LongPressDraggable 抢手势，
            // 结果长按只弹提示、拖不起来。这里改成只能代码触发。
            triggerMode: TooltipTriggerMode.manual,
            child: shell,
          ),
        ),
      ),
    );
  }
}

/// 盾牌式小按钮：⋮ / × 这类挂在胶囊右端的小点击区。
class _ChipAction extends StatelessWidget {
  const _ChipAction({
    required this.icon,
    required this.tooltip,
    required this.onTap,
    this.padded = 3,
  });

  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double padded;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      child: AppInkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: EdgeInsets.all(padded),
          child: Icon(icon, size: 16, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// 组胶囊：组图标 + 组名 + 成员数，用次要色系和节点胶囊区分开。
class GroupChip extends StatelessWidget {
  const GroupChip({
    super.key,
    required this.name,
    required this.members,
    this.type = 'select',
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.tooltip,
  });

  final String name;
  final int members;
  final String type;
  final bool selected;
  final VoidCallback? onTap;

  /// 非空表示这是某个组的成员，可以点 × 移除。
  final VoidCallback? onRemove;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = scheme.secondary;
    final chip = ChipShell(
      spec: ChipSpec.of(context, ChipFamily.group),
      selected: selected,
      accent: accent,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypeSquare(icon: groupIcon(type), color: accent),
          const SizedBox(width: 6),
          Text(
            name,
            style: display(
              13,
              weight: selected ? 600 : 500,
              color: selected ? chipSelectionColor(scheme) : null,
            ),
          ),
          const SizedBox(width: 5),
          Text('$members 成员', style: mono(10, color: scheme.onSurfaceVariant)),
          if (onRemove != null)
            _ChipAction(
              icon: Icons.close,
              tooltip: '从组里移除',
              onTap: onRemove,
              padded: 4,
            ),
        ],
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// 系统策略胶囊：DIRECT 绿、REJECT 红、REJECT-DROP 灰。
class SystemPolicyChip extends StatelessWidget {
  const SystemPolicyChip({
    super.key,
    required this.name,
    this.note,
    this.selected = false,
    this.onTap,
    this.onRemove,
    this.tooltip,
  });

  final String name;

  /// 附加说明，例如 REJECT-DROP 的「不常用」。
  final String? note;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = systemPolicyColor(name, scheme);
    final chip = ChipShell(
      spec: ChipSpec.of(context, ChipFamily.systemPolicy, policy: name),
      selected: selected,
      accent: accent,
      onTap: onTap,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypeSquare(icon: builtinIcon(name), color: accent),
          const SizedBox(width: 6),
          Text(
            name,
            style: mono(
              12,
              color: selected ? chipSelectionColor(scheme) : accent,
              weight: 600,
            ),
          ),
          if (note != null) ...[
            const SizedBox(width: 4),
            Text(note!, style: mono(9.5, color: scheme.onSurfaceVariant)),
          ],
          if (onRemove != null)
            _ChipAction(
              icon: Icons.close,
              tooltip: '从组里移除',
              onTap: onRemove,
              padded: 4,
            ),
        ],
      ),
    );
    return tooltip == null ? chip : Tooltip(message: tooltip!, child: chip);
  }
}

/// 通用名称胶囊：选择列表、添加成员预览用它。
///
/// 按名字自动分派样式：系统策略走 [SystemPolicyChip]，策略组走 [GroupChip]，
/// 其余（节点）用节点样式，这样同一个名字在任何地方看起来都一样。
class NameChip extends StatelessWidget {
  const NameChip({
    super.key,
    required this.name,
    this.icon,
    this.subtitle,
    this.selected = false,
    this.enabled = true,
    this.onTap,
  });

  final String name;
  final IconData? icon;
  final String? subtitle;
  final bool selected;
  final bool enabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isPolicy = Profile.builtinTargets.contains(name);
    final accent = isPolicy ? systemPolicyColor(name, scheme) : scheme.primary;
    final effectiveIcon =
        icon ?? (isPolicy ? builtinIcon(name) : Icons.dns_outlined);
    final fg = !enabled
        ? scheme.onSurfaceVariant.withValues(alpha: 0.6)
        : (selected ? chipSelectionColor(scheme) : scheme.onSurface);
    return ChipShell(
      spec: ChipSpec.of(
        context,
        isPolicy ? ChipFamily.systemPolicy : ChipFamily.name,
        policy: name,
      ),
      selected: selected,
      accent: accent,
      onTap: enabled ? onTap : null,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypeSquare(icon: effectiveIcon, color: accent),
          const SizedBox(width: 6),
          Text(
            name,
            style: mono(12, weight: selected ? 600 : 500, color: fg),
          ),
          if (subtitle != null) ...[
            const SizedBox(width: 4),
            Text(subtitle!, style: hintStyle(context)?.copyWith(fontSize: 10)),
          ],
        ],
      ),
    );
  }
}

/// 规则胶囊：类型小方块 + 规则名 + `→ 目标`，用于「本组规则」和规则选择器。
///
/// 规则页四区的行卡本身已经是胶囊卡（RuleRowCard），不要再套这层。
class RuleChip extends StatelessWidget {
  const RuleChip({
    super.key,
    required this.rule,
    this.selected = false,
    this.onTap,
    this.onDelete,
    this.trailing,
  });

  final RuleEntry rule;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDelete;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final accent = selected ? chipSelectionColor(scheme) : scheme.secondary;
    return ChipShell(
      spec: ChipSpec.of(context, ChipFamily.rule),
      selected: selected,
      accent: accent,
      onTap: onTap,
      padding: const EdgeInsets.fromLTRB(6, 4, 4, 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _TypeSquare(icon: Icons.rule_outlined, color: accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              ruleTitleOf(rule),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: display(12.5, weight: 600),
            ),
          ),
          const SizedBox(width: 6),
          Text(
            '→ ${rule.target}',
            style: mono(10.5, color: scheme.onSurfaceVariant, weight: 600),
          ),
          ?trailing,
          if (onDelete != null)
            _ChipAction(
              icon: Icons.close,
              tooltip: '删除这条规则',
              onTap: onDelete,
              padded: 4,
            ),
        ],
      ),
    );
  }
}

/// 按名字挑一个胶囊：系统策略 → 系统策略胶囊，其余 → 名称胶囊。
///
/// 选择面板（picker_sheet）的胶囊模式用它，保证和「全局出口」行同一外观。
Widget nameChipFor(
  BuildContext context,
  String name, {
  IconData? icon,
  String? subtitle,
  bool selected = false,
  bool enabled = true,
  VoidCallback? onTap,
}) {
  return NameChip(
    name: name,
    icon: icon,
    subtitle: subtitle,
    selected: selected,
    enabled: enabled,
    onTap: onTap,
  );
}
