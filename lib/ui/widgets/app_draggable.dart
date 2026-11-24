import 'package:flutter/gestures.dart' show kLongPressTimeout;
import 'package:material_ui/material_ui.dart';

/// 桌面直接拖动，触摸端沿用长按拿起。
class AppDraggable<T extends Object> extends StatelessWidget {
  const AppDraggable({
    super.key,
    required this.data,
    required this.child,
    required this.feedback,
    this.childWhenDragging,
    this.delay = kLongPressTimeout,
    this.maxSimultaneousDrags,
    this.onDragStarted,
    this.onDragUpdate,
    this.onDragEnd,
  });

  final T data;
  final Widget child;
  final Widget feedback;
  final Widget? childWhenDragging;
  final Duration delay;
  final int? maxSimultaneousDrags;
  final VoidCallback? onDragStarted;
  final DragUpdateCallback? onDragUpdate;
  final DragEndCallback? onDragEnd;

  @override
  Widget build(BuildContext context) {
    if (Theme.of(context).platform == TargetPlatform.windows) {
      return MouseRegion(
        cursor: SystemMouseCursors.grab,
        child: Draggable<T>(
          data: data,
          feedback: feedback,
          childWhenDragging: childWhenDragging,
          maxSimultaneousDrags: maxSimultaneousDrags,
          onDragStarted: onDragStarted,
          onDragUpdate: onDragUpdate,
          onDragEnd: onDragEnd,
          child: child,
        ),
      );
    }
    return LongPressDraggable<T>(
      data: data,
      feedback: feedback,
      childWhenDragging: childWhenDragging,
      delay: delay,
      maxSimultaneousDrags: maxSimultaneousDrags,
      onDragStarted: onDragStarted,
      onDragUpdate: onDragUpdate,
      onDragEnd: onDragEnd,
      child: child,
    );
  }
}
