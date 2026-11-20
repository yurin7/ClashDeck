import 'package:material_ui/material_ui.dart';

import '../pulse_entry.dart';
import 'horizontal_drag.dart';

/// 手势层：PageView 永久禁用滚动，所有水平拖拽都在这里解释。
///
/// - 遮罩可见（reveal > 0 或正在动画）：只改 [reveal]，松手后由
///   [onSettle] 决定开合，页面索引不动。
/// - 遮罩关闭：第 0 页向右拖用来拉出抽屉；其余方向累计位移，松手按
///   距离/速度翻页。
class PulseSwipeArea extends StatefulWidget {
  const PulseSwipeArea({
    super.key,
    required this.child,
    required this.index,
    required this.pageCount,
    required this.reveal,
    required this.onOpenPulse,
    required this.onSettle,
    required this.onPageChange,
  });

  final Widget child;
  final int index;
  final int pageCount;

  /// 遮罩进度 0..1，由外层 AnimationController 驱动。
  final AnimationController reveal;

  /// 关闭态右拖越过阈值后调用：外层负责把遮罩打开。
  final VoidCallback onOpenPulse;

  /// 遮罩可见时松手：true = 展开，false = 收起。
  final void Function(bool open) onSettle;

  /// 关闭态左/右拖松手后切页。
  final void Function(int index) onPageChange;

  @override
  State<PulseSwipeArea> createState() => _PulseSwipeAreaState();
}

class _PulseSwipeAreaState extends State<PulseSwipeArea> {
  /// 本次拖拽累计位移（关闭态用于开抽屉/翻页判定）。
  double _dx = 0;

  /// 起手时抽屉是否已经打开：是则本次拖拽只负责开合，不参与翻页。
  bool _drawerDrag = false;

  void _onStart() {
    _dx = 0;
    _drawerDrag = widget.reveal.value > 0.001;
  }

  void _onUpdate(DragUpdateDetails details) {
    final delta = details.delta.dx;
    final width = MediaQuery.sizeOf(context).width;
    final panelWidth = pulseDrawerPanelWidth(width);
    if (panelWidth <= 0) return;

    if (widget.reveal.value > 0) {
      widget.reveal.value = (widget.reveal.value + delta / panelWidth).clamp(
        0.0,
        1.0,
      );
      return;
    }

    if (widget.index == 0 && delta > 0) {
      _dx = pulseForwardDrag(dx: _dx, delta: delta);
      if (_dx < kPulseOverscrollStartDx) return;
      widget.onOpenPulse();
      widget.reveal.value = pulseDrawerProgress(
        dragDx: _dx,
        panelWidth: panelWidth,
      );
      return;
    }

    _dx += delta;
  }

  void _onEnd(DragEndDetails details) {
    final velocity = details.velocity.pixelsPerSecond.dx;
    if (_drawerDrag || widget.reveal.value > 0.001) {
      _drawerDrag = false;
      widget.onSettle(
        pulseDrawerShouldOpen(
          progress: widget.reveal.value,
          velocity: velocity,
        ),
      );
      _dx = 0;
      return;
    }

    final dx = _dx;
    _dx = 0;
    final width = MediaQuery.sizeOf(context).width;
    if (dx.abs() < width * 0.25 && velocity.abs() < 400) return;
    final next = dx < 0 ? widget.index + 1 : widget.index - 1;
    if (next < 0 || next >= widget.pageCount) return;
    widget.onPageChange(next);
  }

  @override
  Widget build(BuildContext context) {
    return HorizontalDragArea(
      behavior: HitTestBehavior.translucent,
      onStart: _onStart,
      onUpdate: _onUpdate,
      onEnd: _onEnd,
      child: widget.child,
    );
  }
}
