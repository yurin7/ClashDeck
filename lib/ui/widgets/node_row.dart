import 'package:material_ui/material_ui.dart';

import '../../core/model/profile.dart';
import '../chips.dart';
import '../theme.dart';
import '../widgets.dart';
import 'app_ink.dart';

/// 节点列表里的行：左侧协议方块、中间名称 +「协议 · 上次延迟」、右侧
/// 「当前」徽章与 ⋮ 菜单。
///
/// 交互与旧胶囊保持一致：
/// - 点整行 = 编辑节点；
/// - 长按整行 = 拖到策略组（[DragNodeData] 携带来源组）；
/// - 左滑 = 删除（统一走 [SlidableRow]，确认框由调用方负责）。
class NodeRow extends StatelessWidget {
  const NodeRow({
    super.key,
    required this.node,
    required this.delayText,
    required this.selected,
    required this.open,
    required this.onOpenChanged,
    required this.onTap,
    required this.onMenu,
    required this.onDelete,
    this.fromGroup,
    this.radius = 10,
  });

  final ProxyEntry node;

  /// 上次测速结果：`—` 未测速、`123 ms`、`超时`。
  final String delayText;

  /// 是否是所属组当前的出口（显示「当前」徽章）。
  final bool selected;

  /// 左滑展开态（由列表统一持有，保证单行互斥）。
  final bool open;
  final ValueChanged<bool> onOpenChanged;

  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final VoidCallback onDelete;

  /// 拖拽来源组；节点列表里恒为 null。
  final String? fromGroup;

  final double radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final br = BorderRadius.circular(radius);
    final content = Material(
      color: scheme.surfaceContainerHigh.withValues(alpha: 0.55),
      borderRadius: br,
      child: LongPressDraggable<DragNodeData>(
        data: DragNodeData(node.name, fromGroup),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: 240,
            child: NodeChip(
              node: node,
              fromGroup: fromGroup,
              onOpen: onTap,
              onMove: () {},
              onDelete: onDelete,
              onRemove: null,
            ),
          ),
        ),
        child: AppInkWell(
          borderRadius: br,
          onTap: onTap,
          child: SizedBox(
            height: 60,
            child: Row(
              children: [
                const SizedBox(width: Insets.md),
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: scheme.primary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: scheme.primary.withValues(alpha: 0.20),
                    ),
                  ),
                  child: Text(
                    NodeChip.typeBadge(node.type),
                    style: mono(12, color: scheme.primary, weight: 700),
                  ),
                ),
                const SizedBox(width: Insets.md),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        node.name,
                        style: display(14.5, weight: 600, letterSpacing: -0.1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${node.type} · $delayText',
                        style: mono(
                          10.5,
                          color: scheme.onSurfaceVariant,
                          letterSpacing: 0.2,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                if (selected) ...[
                  const SizedBox(width: Insets.xs),
                  Pill(label: '当前', color: scheme.primary, dense: true),
                ],
                if (onMenu != null)
                  IconButton(
                    tooltip: '节点操作',
                    visualDensity: VisualDensity.compact,
                    constraints: const BoxConstraints(
                      minWidth: 44,
                      minHeight: 44,
                    ),
                    onPressed: onMenu,
                    icon: const Icon(Icons.more_vert, size: 20),
                  )
                else
                  const SizedBox(width: Insets.sm),
              ],
            ),
          ),
        ),
      ),
    );

    return SlidableRow(
      open: open,
      onOpenChanged: onOpenChanged,
      actionLabel: '删除',
      borderRadius: br,
      onAction: onDelete,
      child: content,
    );
  }
}
