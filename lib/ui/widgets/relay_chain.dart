import 'dart:math' as math;

import 'package:flutter/foundation.dart' show listEquals;
import 'package:flutter/rendering.dart'
    show BoxHitTestResult, PaintingContext, PipelineOwner, RenderProxyBox;
import 'package:material_ui/material_ui.dart';

import '../../core/model/profile.dart';
import '../chips.dart';
import '../motion.dart';
import '../theme.dart';
import 'app_ink.dart';
import 'delay_badge.dart';
import 'drag_state.dart';

/// 链内换位：从第 [from] 阶拖到某个插入间隙。
class RelayMemberDragData {
  const RelayMemberDragData({required this.group, required this.from});

  final String group;
  final int from;
}

/// 链式代理的横向链条：`①节点 → ②节点 → ③节点 → ＋`。
///
/// 链节拖过其它胶囊时预览换位，松手后写回顺序。
class RelayChain extends StatefulWidget {
  const RelayChain({
    super.key,
    required this.group,
    required this.profile,
    required this.delays,
    required this.approx,
    required this.onOpen,
    required this.onDelete,
    required this.onRemove,
    required this.onInsertAt,
    required this.onMoveLeft,
    required this.onMoveRight,
    required this.onMoveMember,
    required this.onAddMember,
    this.onSelect,
    this.onMenu,
  });

  final GroupEntry group;
  final Profile profile;
  final Map<String, int?> delays;
  final Set<String> approx;

  final void Function(ProxyEntry node) onOpen;
  final void Function(ProxyEntry node) onDelete;
  final void Function(String name) onRemove;
  final void Function(String node, int index) onInsertAt;
  final void Function(int from, int to) onMoveLeft;
  final void Function(int from, int to) onMoveRight;
  final void Function(int from, int to) onMoveMember;
  final VoidCallback onAddMember;
  final void Function(String name)? onSelect;
  final void Function(ProxyEntry node, int index)? onMenu;

  @override
  State<RelayChain> createState() => _RelayChainState();
}

typedef _LinkId = ({String name, int occurrence});

class _RelayChainState extends State<RelayChain>
    with SingleTickerProviderStateMixin {
  final _linkKeys = <_LinkId, GlobalKey>{};
  final _wireKey = GlobalKey();
  late final _clock = AnimationController(vsync: this, value: 1);
  late Animation<double> _progress = _clock.drive(
    CurveTween(curve: Motion.normal.enter),
  );

  List<_LinkId>? _preview;
  _LinkId? _held;
  Offset? _lastDragOffset;
  ({_LinkId target, Offset at})? _lastSwap;
  ({String name, int index, Offset offset})? _pendingDrop;
  Map<_LinkId, Offset> _origins = const {};
  _LinkId? _landing;

  List<_LinkId> _linkIds(List<String> members) {
    final counts = <String, int>{};
    return [
      for (final name in members)
        (
          name: name,
          occurrence: counts.update(name, (n) => n + 1, ifAbsent: () => 0),
        ),
    ];
  }

  Rect? _boundsOf(_LinkId id) {
    final box = _linkKeys[id]?.currentContext?.findRenderObject();
    return box is RenderBox && box.attached && box.hasSize
        ? box.localToGlobal(Offset.zero) & box.size
        : null;
  }

  Map<_LinkId, Offset> _positions(List<_LinkId> ids) => {
    for (final id in ids)
      if (_boundsOf(id) case final Rect bounds) id: bounds.topLeft,
  };

  void _animate(
    Map<_LinkId, Offset> origins,
    Duration duration, {
    _LinkId? landing,
  }) {
    _origins = origins;
    _landing = landing;
    _progress = _clock.drive(CurveTween(curve: Motion.of(context).enter));
    _clock.duration = duration;
    _clock.forward(from: 0);
  }

  void _clearDrag() {
    _preview = null;
    _held = null;
    _lastDragOffset = null;
    _lastSwap = null;
    _pendingDrop = null;
  }

  @override
  void didUpdateWidget(covariant RelayChain oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.group.name != oldWidget.group.name) {
      _linkKeys.clear();
      _clearDrag();
      _clock.value = 1;
      _origins = const {};
      _landing = null;
      return;
    }
    if (listEquals(widget.group.members, oldWidget.group.members)) return;

    final origins = _positions(_preview ?? _linkIds(oldWidget.group.members));
    final currentIds = _linkIds(widget.group.members);
    final drop = _pendingDrop;
    _LinkId? landing;
    if (drop != null &&
        drop.index < currentIds.length &&
        currentIds[drop.index].name == drop.name) {
      landing = currentIds[drop.index];
      origins[landing] = drop.offset;
    }
    _clearDrag();
    final keep = currentIds.toSet();
    _linkKeys.removeWhere((id, _) => !keep.contains(id));
    _animate(origins, Motion.of(context).relayReorder, landing: landing);
  }

  @override
  void dispose() {
    _clock.dispose();
    super.dispose();
  }

  bool _accepts(Object data) => switch (data) {
    RelayMemberDragData(:final group, :final from) =>
      group == widget.group.name &&
          from >= 0 &&
          from < widget.group.members.length,
    DragNodeData(:final node) => !widget.group.members.contains(node),
    _ => false,
  };

  void _previewSwap(DragTargetDetails<Object> details) {
    final data = details.data;
    final size = dragState.feedbackSize;
    if (data is! RelayMemberDragData || size == null || !_accepts(data)) return;

    final original = _linkIds(widget.group.members);
    final order = _preview ?? original;
    final held = original[data.from];
    final slot = _boundsOf(held);
    if (slot == null) return;
    final from = order.indexOf(held);
    final dragged = details.offset & size;
    final step =
        details.offset -
        (_lastDragOffset ?? dragState.sourceRect?.topLeft ?? details.offset);
    _lastDragOffset = details.offset;

    int? nextIndex;
    var bestOverlap = 0.0;
    for (final (index, id) in order.indexed) {
      if (id == held) continue;
      final target = _boundsOf(id);
      if (target == null || !target.overlaps(dragged)) continue;
      final last = _lastSwap;
      if (last != null &&
          last.target == id &&
          (dragged.center - last.at).distance < Insets.sm) {
        continue;
      }

      final overlap = dragged.intersect(target);
      final acrossRows =
          (target.center.dy - slot.center.dy).abs() >
          math.min(slot.height, target.height) / 2;
      final forward = index > from;
      if (!_crossesEdge(
        dragged,
        target,
        overlap,
        step,
        forward: forward,
        vertical: acrossRows,
      )) {
        continue;
      }
      final area = overlap.width * overlap.height;
      if (area > bestOverlap) {
        bestOverlap = area;
        nextIndex = index;
      }
    }

    if (nextIndex == null) return;
    final target = order[nextIndex];
    final next = [...order]
      ..removeAt(from)
      ..insert(nextIndex, held);
    final origins = _positions(order);
    setState(() {
      _preview = next;
      _held = held;
      _lastSwap = (target: target, at: dragged.center);
      _animate(origins, Motion.of(context).relayPreview);
    });
  }

  bool _crossesEdge(
    Rect dragged,
    Rect target,
    Rect overlap,
    Offset step, {
    required bool forward,
    required bool vertical,
  }) {
    final motion = vertical ? step.dy : step.dx;
    if (step == Offset.zero ||
        (!vertical && motion == 0) ||
        (forward ? motion < 0 : motion > 0)) {
      return false;
    }

    final crossOverlap = vertical ? overlap.width : overlap.height;
    final crossSize = vertical
        ? math.min(dragged.width, target.width)
        : math.min(dragged.height, target.height);
    if (crossOverlap < crossSize / 2) return false;

    final start = vertical ? target.top : target.left;
    final end = vertical ? target.bottom : target.right;
    final draggedStart = vertical ? dragged.top : dragged.left;
    final draggedEnd = vertical ? dragged.bottom : dragged.right;
    final threshold = (end - start) * 0.30;
    final entryStart = forward ? start : end - threshold;
    final entryEnd = forward ? start + threshold : end;
    final covered =
        math.min(draggedEnd, entryEnd) - math.max(draggedStart, entryStart);
    return covered >= math.min(threshold, draggedEnd - draggedStart) - 0.01;
  }

  void _leave() {
    final preview = _preview;
    final origins = preview == null ? null : _positions(preview);
    _clearDrag();
    if (origins != null) {
      setState(() => _animate(origins, Motion.of(context).relayPreview));
    }
  }

  void _accept(DragTargetDetails<Object> details) {
    final data = details.data;
    if (!_accepts(data)) return;
    dragState.markAccepted();
    final ids = _linkIds(widget.group.members);
    if (data is RelayMemberDragData) {
      final from = data.from;
      final held = ids[from];
      final to = _preview?.indexOf(held) ?? from;
      if (to == from) {
        _leave();
        return;
      }
      _rememberDrop(held.name, to, details.offset);
      widget.onMoveMember(from, to > from ? to + 1 : to);
    } else if (data is DragNodeData) {
      final center =
          (details.offset & (dragState.feedbackSize ?? Size.zero)).center;
      final gap = _nearestInsertion(ids, center);
      _rememberDrop(data.node, gap, details.offset);
      widget.onInsertAt(data.node, gap);
    }
  }

  int _nearestInsertion(List<_LinkId> ids, Offset center) {
    var gap = ids.length;
    var distance = double.infinity;
    for (final (index, id) in ids.indexed) {
      final bounds = _boundsOf(id);
      if (bounds == null) continue;
      final delta = (center - bounds.center).distanceSquared;
      if (delta < distance) {
        distance = delta;
        gap = center.dx < bounds.center.dx ? index : index + 1;
      }
    }
    return gap;
  }

  void _rememberDrop(String name, int index, Offset offset) {
    final drop = (name: name, index: index, offset: offset);
    _pendingDrop = drop;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _pendingDrop == drop) _leave();
    });
  }

  Widget _link(
    _LinkId id,
    int index,
    int sourceIndex,
    double maxWidth,
    double maxNameWidth,
  ) {
    final name = id.name;
    final link = _ChainLink(
      key: _linkKeys.putIfAbsent(id, GlobalKey.new),
      index: index,
      sourceIndex: sourceIndex,
      node: widget.profile.proxyByName[name],
      fallbackName: name,
      groupName: widget.group.name,
      maxWidth: maxWidth,
      maxNameWidth: maxNameWidth,
      placeholderSize: id == _held ? dragState.feedbackSize : null,
      delayText: widget.delays.containsKey(name)
          ? formatDelay(
              widget.delays[name],
              approx: widget.approx.contains(name),
            )
          : null,
      onOpen: widget.onOpen,
      onDelete: widget.onDelete,
      onRemove: widget.onRemove,
      onSelect: widget.onSelect,
      onMoveLeft: sourceIndex == 0
          ? null
          : () => widget.onMoveLeft(sourceIndex, sourceIndex - 1),
      onMoveRight: sourceIndex == widget.group.members.length - 1
          ? null
          : () => widget.onMoveRight(sourceIndex, sourceIndex + 1),
      onMenu: widget.onMenu,
    );
    return _RelayTranslation(
      key: ValueKey(id),
      progress: _progress,
      origin: _origins[id],
      child: id == _landing
          ? FadeTransition(
              opacity: _progress.drive(Tween<double>(begin: 0.92, end: 1)),
              child: link,
            )
          : link,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final source = _linkIds(widget.group.members);
    final order = _preview ?? source;
    final sourceIndexes = {for (final (index, id) in source.indexed) id: index};
    return Padding(
      padding: const EdgeInsets.only(top: Insets.md, right: Insets.sm),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final linkWidth = (constraints.maxWidth - Insets.md).clamp(
            140.0,
            double.infinity,
          );
          final nameWidth = (linkWidth - 150).clamp(48.0, 200.0);
          final links = SizedBox(
            width: double.infinity,
            child: CustomPaint(
              key: _wireKey,
              painter: _RelayWires(
                canvasKey: _wireKey,
                links: [
                  for (final id in order)
                    _linkKeys.putIfAbsent(id, GlobalKey.new),
                ],
                color: scheme.outline,
                repaint: _clock,
              ),
              child: Wrap(
                spacing: Insets.lg,
                runSpacing: Insets.lg,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  for (final (index, id) in order.indexed)
                    _link(id, index, sourceIndexes[id]!, linkWidth, nameWidth),
                  if (source.length >= 2) _AddLink(onTap: widget.onAddMember),
                ],
              ),
            ),
          );
          return DragTarget<Object>(
            onWillAcceptWithDetails: (details) => _accepts(details.data),
            onMove: _previewSwap,
            onLeave: (_) => _leave(),
            onAcceptWithDetails: _accept,
            builder: (context, _, _) {
              if (source.length >= 2) return links;
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (source.isNotEmpty) ...[
                    links,
                    const SizedBox(height: Insets.sm),
                  ],
                  Text(
                    '链式代理至少需要 2 个节点：点右上 ⊕ 添加，或把节点拖进来。',
                    style: hintStyle(context),
                  ),
                  const SizedBox(height: Insets.sm),
                  _AddLink(onTap: widget.onAddMember),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

class _ChainLink extends StatelessWidget {
  const _ChainLink({
    super.key,
    required this.index,
    required this.sourceIndex,
    required this.node,
    required this.fallbackName,
    required this.groupName,
    required this.delayText,
    required this.placeholderSize,
    required this.maxWidth,
    required this.maxNameWidth,
    required this.onOpen,
    required this.onDelete,
    required this.onRemove,
    required this.onMoveLeft,
    required this.onMoveRight,
    this.onSelect,
    this.onMenu,
  });

  final int index;
  final int sourceIndex;
  final ProxyEntry? node;
  final String fallbackName;
  final String groupName;
  final String? delayText;
  final Size? placeholderSize;

  /// 链节整体最大宽度（含胶囊、徽标占位），避免把卡片撑出边界。
  final double maxWidth;
  final double maxNameWidth;
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
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: InputChip(
          label: Text(
            '$fallbackName（内核里不存在）',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          avatar: Icon(Icons.help_outline, size: 16, color: scheme.error),
          onDeleted: () => onRemove(fallbackName),
        ),
      );
    }
    final placeholder = placeholderSize;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: NodeChip(
            node: proxy,
            fromGroup: groupName,
            dragData: RelayMemberDragData(group: groupName, from: sourceIndex),
            dragPlaceholder: placeholder == null
                ? null
                : SizedBox.fromSize(
                    size: placeholder,
                    child: CustomPaint(painter: _DashedSlot(scheme.primary)),
                  ),
            onOpen: () => onOpen(proxy),
            onMove: () => onOpen(proxy),
            onDelete: () => onDelete(proxy),
            onRemove: () => onRemove(fallbackName),
            onMenu: onMenu == null && onMoveLeft == null && onMoveRight == null
                ? null
                : () => _showMenu(context),
            onSelect: onSelect == null ? null : () => onSelect!(fallbackName),
            delayText: delayText,
            maxNameWidth: maxNameWidth,
          ),
        ),
        if (placeholder == null)
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
        if (proxy != null) onMenu!(proxy, sourceIndex);
      case 'left':
        onMoveLeft?.call();
      case 'right':
        onMoveRight?.call();
      case 'remove':
        onRemove(fallbackName);
    }
  }
}

/// 在 Wrap 完成布局后计算实际位移，包含换行时的纵向距离。
class _RelayTranslation extends SingleChildRenderObjectWidget {
  const _RelayTranslation({
    super.key,
    required this.progress,
    required this.origin,
    required super.child,
  });

  final Animation<double> progress;
  final Offset? origin;

  @override
  _RenderRelayTranslation createRenderObject(BuildContext context) =>
      _RenderRelayTranslation(progress, origin);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderRelayTranslation renderObject,
  ) => renderObject.update(progress, origin);
}

class _RenderRelayTranslation extends RenderProxyBox {
  _RenderRelayTranslation(this._progress, this._origin);

  Animation<double> _progress;
  Offset? _origin;
  Offset? _distance;

  void update(Animation<double> progress, Offset? origin) {
    if (_progress == progress && _origin == origin) return;
    if (attached) _progress.removeListener(_onTick);
    _progress = progress;
    _origin = origin;
    _distance = null;
    if (attached) _progress.addListener(_onTick);
    _onTick();
  }

  void _onTick() {
    markNeedsPaint();
    markNeedsSemanticsUpdate();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(_onTick);
  }

  @override
  void detach() {
    _progress.removeListener(_onTick);
    super.detach();
  }

  Offset get _translation {
    final remaining = 1 - _progress.value;
    if (remaining == 0) return Offset.zero;
    final origin = _origin;
    final distance = _distance ??= origin == null
        ? const Offset(Insets.sm, 0)
        : origin - localToGlobal(Offset.zero);
    return distance * remaining;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset + _translation);
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final shift = _translation;
    transform.translateByDouble(shift.dx, shift.dy, 0, 1);
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _translation,
        position: position,
        hitTest: (result, translated) =>
            super.hitTestChildren(result, position: translated),
      );
}

class _RelayWires extends CustomPainter {
  _RelayWires({
    required this.canvasKey,
    required this.links,
    required this.color,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final GlobalKey canvasKey;
  final List<GlobalKey> links;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final layout = canvasKey.currentContext?.findRenderObject();
    if (layout is! RenderBox || !layout.attached) return;
    final wire = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true;
    final port = Paint()..color = color;

    Rect? previous;
    for (final key in links) {
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.attached || !box.hasSize) {
        previous = null;
        continue;
      }
      final bounds =
          box.localToGlobal(Offset.zero, ancestor: layout) & box.size;
      final from = previous;
      previous = bounds;
      if (from == null || from.overlaps(bounds)) continue;

      final start = from.centerRight.translate(0, Insets.xs);
      final end = bounds.centerLeft.translate(0, -Insets.xs);
      final path = Path()..moveTo(start.dx, start.dy);
      if (end.dx >= start.dx) {
        final bend = (end.dx - start.dx) / 2;
        path.cubicTo(
          start.dx + bend,
          start.dy,
          end.dx - bend,
          end.dy,
          end.dx,
          end.dy,
        );
      } else if ((bounds.center.dy - from.center.dy).abs() >= Insets.sm) {
        // 换行处沿行间空白回到下一行的输入端。
        final lane = (start.dy + end.dy) / 2;
        path
          ..cubicTo(
            start.dx + Insets.sm,
            start.dy,
            start.dx + Insets.sm,
            lane,
            start.dx,
            lane,
          )
          ..lineTo(end.dx, lane)
          ..cubicTo(
            end.dx - Insets.sm,
            lane,
            end.dx - Insets.sm,
            end.dy,
            end.dx,
            end.dy,
          );
      } else {
        continue;
      }
      canvas.drawPath(path, wire);
      canvas.drawCircle(start, 2, port);
      canvas.drawCircle(end, 2, port);
    }
  }

  @override
  bool shouldRepaint(_RelayWires oldDelegate) =>
      color != oldDelegate.color || !listEquals(links, oldDelegate.links);
}

class _DashedSlot extends CustomPainter {
  const _DashedSlot(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final bounds = RRect.fromRectAndRadius(
      (Offset.zero & size).deflate(0.75),
      Radiuses.chip,
    );
    canvas.drawRRect(bounds, Paint()..color = color.withValues(alpha: 0.07));
    final path = Path()..addRRect(bounds);
    final dash = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    for (final edge in path.computeMetrics()) {
      for (var start = 0.0; start < edge.length; start += 7) {
        canvas.drawPath(
          edge.extractPath(start, math.min(start + 4, edge.length)),
          dash,
        );
      }
    }
  }

  @override
  bool shouldRepaint(_DashedSlot oldDelegate) => color != oldDelegate.color;
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
