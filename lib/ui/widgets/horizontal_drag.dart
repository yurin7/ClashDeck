import 'package:material_ui/material_ui.dart';

/// 横向拖拽代理：把 [GestureDetector] 的 onHorizontalDrag* 收进共享封装。
///
/// Pulse 抽屉需要「跟手 + 松手按速度判定」，与行级左滑（`SlidableRow`）是
/// 两种不同手势；这里只做一层薄封装，避免业务页散写 `onHorizontalDrag*`，
/// 也让 UI 自检保持 0 基线。
class HorizontalDragArea extends StatelessWidget {
  const HorizontalDragArea({
    super.key,
    required this.child,
    this.onStart,
    this.onUpdate,
    this.onEnd,
    this.behavior = HitTestBehavior.opaque,
  });

  final Widget child;

  /// 按下时回调，用于清零累计位移。
  final VoidCallback? onStart;

  /// 每帧回调，参数是「累计位移」的增量（向右为正）。
  final ValueChanged<DragUpdateDetails>? onUpdate;

  /// 松手回调，携带主方向速度（向右为正，px/s）。
  final ValueChanged<DragEndDetails>? onEnd;

  final HitTestBehavior behavior;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: behavior,
      onHorizontalDragStart: onStart == null ? null : (_) => onStart!(),
      onHorizontalDragUpdate: onUpdate,
      onHorizontalDragEnd: onEnd,
      child: child,
    );
  }
}
