import 'package:material_ui/material_ui.dart';

import '../../core/model/profile.dart';
import '../chips.dart';
import '../motion.dart';
import '../theme.dart';
import 'app_ink.dart';
import 'delay_badge.dart';

/// 链式代理的横向链条：`①节点 → ②节点 → ③节点 → ＋`。
///
/// 每阶左上角有顺序徽标，阶与阶之间、链条末尾各留一个透明拖放间隙，
/// 让节点既能从别的组拖进来，也能在本链内调整顺序。
class RelayChain extends StatelessWidget {
  const RelayChain({
    super.key,
    required this.group,
    required this.profile,
    required this.delays,
    required this.approx,
    required this.selectedName,
    required this.onOpen,
    required this.onDelete,
    required this.onRemove,
    required this.onInsertAt,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onAddMember,
    this.onSelect,
    this.onMenu,
  });

  final GroupEntry group;
  final Profile profile;
  final Map<String, int?> delays;
  final Set<String> approx;
  final String? selectedName;
  final void Function(ProxyEntry node) onOpen;
  final void Function(ProxyEntry node) onDelete;
  final void Function(String name) onRemove;
  final void Function(String node, int index) onInsertAt;
  final void Function(int from, int to) onMoveLeft;
  final void Function(int from, int to) onMoveRight;
  final VoidCallback onAddMember;
  final void Function(String name)? onSelect;
  final void Function(ProxyEntry node, int index)? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final members = group.members;
    if (members.length < 2) {
      return Padding(
        padding: const EdgeInsets.only(top: Insets.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('链式代理至少需要 2 个节点：点右上 ⊕ 添加，或把节点拖进来。', style: hintStyle(context)),
            const SizedBox(height: Insets.sm),
            _AddLink(onTap: onAddMember),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(top: Insets.md, right: Insets.sm),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < members.length; i++) ...[
              _GapTarget(index: i, group: group, onInsertAt: onInsertAt),
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Insets.xs),
                  child: Icon(
                    Icons.arrow_right_alt_rounded,
                    size: 18,
                    color: scheme.outline,
                  ),
                ),
              _ChainLink(
                index: i,
                total: members.length,
                node: profile.proxyByName[members[i]],
                fallbackName: members[i],
                groupName: group.name,
                selected: selectedName == members[i],
                delayText: delays.containsKey(members[i])
                    ? formatDelay(
                        delays[members[i]],
                        approx: approx.contains(members[i]),
                      )
                    : null,
                onOpen: onOpen,
                onDelete: onDelete,
                onRemove: onRemove,
                onSelect: onSelect,
                onMoveLeft: i == 0 ? null : () => onMoveLeft(i, i - 1),
                onMoveRight: i == members.length - 1
                    ? null
                    : () => onMoveRight(i, i + 1),
                onMenu: onMenu,
              ),
            ],
            _GapTarget(
              index: members.length,
              group: group,
              onInsertAt: onInsertAt,
            ),
            _AddLink(onTap: onAddMember),
          ],
        ),
      ),
    );
  }
}

class _ChainLink extends StatelessWidget {
  const _ChainLink({
    required this.index,
    required this.total,
    required this.node,
    required this.fallbackName,
    required this.groupName,
    required this.selected,
    required this.delayText,
    required this.onOpen,
    required this.onDelete,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
    this.onSelect,
    this.onMenu,
  });

  final int index;
  final int total;
  final ProxyEntry? node;
  final String fallbackName;
  final String groupName;
  final bool selected;
  final String? delayText;
  final void Function(ProxyEntry node) onOpen;
  final void Function(ProxyEntry node) onDelete;
  final void Function(String name) onRemove;
  final VoidCallback? onMoveLeft;
  final VoidCallback? onMoveRight;
  final void Function(String name)? onSelect;
  final void Function(ProxyEntry node, int index)? onMenu;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final proxy = node;
    if (proxy == null) {
      return InputChip(
        label: Text('$fallbackName（内核里不存在）'),
        avatar: Icon(Icons.help_outline, size: 16, color: scheme.error),
        onDeleted: () => onRemove(fallbackName),
      );
    }
    return Stack(
      clipBehavior: Clip.none,
      children: [
        NodeChip(
          node: proxy,
          fromGroup: groupName,
          onOpen: () => onOpen(proxy),
          onMove: () => onOpen(proxy),
          onDelete: () => onDelete(proxy),
          onRemove: () => onRemove(fallbackName),
          onMenu: onMenu == null && onMoveLeft == null && onMoveRight == null
              ? null
              : () => _showMenu(context),
          onSelect: onSelect == null ? null : () => onSelect!(fallbackName),
          selected: selected,
          delayText: delayText,
        ),
        Positioned(
          left: -6,
          top: -6,
          child: Container(
            width: 16,
            height: 16,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.surface, width: 1.5),
            ),
            child: Text(
              '${index + 1}',
              style: TextStyle(
                fontSize: 9,
                height: 1,
                fontWeight: FontWeight.w700,
                color: scheme.onPrimary,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final box = context.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) return;
    final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
    final proxy = node;
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy + box.size.height,
        origin.dx + box.size.width,
        origin.dy + box.size.height,
      ),
      items: [
        if (proxy != null && onMenu != null)
          PopupMenuItem(value: 'edit', child: Text('编辑节点')),
        if (onMoveLeft != null)
          const PopupMenuItem(value: 'left', child: Text('前移一位')),
        if (onMoveRight != null)
          const PopupMenuItem(value: 'right', child: Text('后移一位')),
        const PopupMenuItem(value: 'remove', child: Text('移出链式代理')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'edit':
        if (proxy != null) onMenu!(proxy, index);
      case 'left':
        onMoveLeft?.call();
      case 'right':
        onMoveRight?.call();
      case 'remove':
        onRemove(fallbackName);
    }
  }
}

class _GapTarget extends StatelessWidget {
  const _GapTarget({
    required this.index,
    required this.group,
    required this.onInsertAt,
  });

  final int index;
  final GroupEntry group;
  final void Function(String node, int index) onInsertAt;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DragTarget<Object>(
      onWillAcceptWithDetails: (details) {
        final data = details.data;
        return data is DragNodeData && !group.members.contains(data.node);
      },
      onAcceptWithDetails: (details) {
        final data = details.data;
        if (data is DragNodeData) onInsertAt(data.node, index);
      },
      builder: (context, candidate, _) {
        final active = candidate.isNotEmpty;
        return AnimatedContainer(
          duration: Motion.of(context).fast,
          width: active ? 10 : 6,
          height: 36,
          margin: const EdgeInsets.symmetric(horizontal: 3),
          decoration: BoxDecoration(
            color: active ? scheme.primary : Colors.transparent,
            borderRadius: BorderRadius.circular(3),
          ),
        );
      },
    );
  }
}

class _AddLink extends StatelessWidget {
  const _AddLink({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: Insets.sm),
      child: AppInkWell(
        onTap: onTap,
        borderRadius: BorderRadius.all(Radiuses.chip),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: Insets.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.all(Radiuses.chip),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.add, size: 16, color: scheme.onSurfaceVariant),
              const SizedBox(width: 4),
              Text(
                '加一阶',
                style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
