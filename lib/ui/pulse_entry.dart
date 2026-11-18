import 'package:material_ui/material_ui.dart';

/// 负一屏（Pulse）入口判定：在概览（PageView 第一页）继续向右拖，
/// 累计位移超过 96dp 或向右甩得够快（>350px/s）就打开。
///
/// 为什么不用 GestureDetector：PageView 自己就是横向 Scrollable，横向拖拽
/// 会先被它的手势竞技场吃掉，概览页里的 `onHorizontalDrag*` 根本收不到
/// （0.3.0 实测：左滑/右滑都打不开 Pulse）。改成听 PageView 在左边界产生
/// 的 overscroll：手指还在往右拖、页面却已经到头的这段「拖不动」的位移
/// 才代表用户想拉负一屏。
bool pulseSwipeShouldOpen({required double dragDx, required double velocity}) =>
    dragDx > 96 || velocity > 350;

/// 包在 `PageView` 外面，只在第一页向右拖出 overscroll 时触发 [onOpen]。
///
/// 只接受 `depth == 0` 的通知（PageView 自己），避免概览里横向滚动的胶囊行
/// 到边界时也冒出 overscroll 把负一屏误拉出来。
class PulseSwipeEntry extends StatefulWidget {
  const PulseSwipeEntry({
    super.key,
    required this.enabled,
    required this.onOpen,
    required this.child,
  });

  /// 只有回到第一页（概览）时才允许触发。
  final bool enabled;

  final VoidCallback onOpen;
  final Widget child;

  @override
  State<PulseSwipeEntry> createState() => _PulseSwipeEntryState();
}

class _PulseSwipeEntryState extends State<PulseSwipeEntry> {
  double _dragged = 0;
  bool _fired = false;

  void _reset() {
    _dragged = 0;
    _fired = false;
  }

  bool _onNotification(ScrollNotification notification) {
    // 只认 PageView 自己的通知：嵌套滚动（横向胶囊行等）深度 > 0，忽略。
    if (notification.depth != 0) return false;
    if (notification is ScrollStartNotification) {
      _reset();
      return false;
    }
    if (notification is ScrollEndNotification) {
      _reset();
      return false;
    }
    if (!widget.enabled || _fired || notification is! OverscrollNotification) {
      return false;
    }
    // 第一页再往右拖，PageView 的 offset 会尝试小于 0；用累加位移判断
    // 方向，避免依赖不同 physics 下 overscroll 的正负号。
    final delta = notification.dragDetails?.delta.dx ?? 0;
    if (delta > 0) {
      _dragged += delta;
    } else if (delta == 0 && notification.overscroll < 0) {
      _dragged += -notification.overscroll;
    }
    final velocity = notification.velocity;
    if (pulseSwipeShouldOpen(dragDx: _dragged, velocity: velocity)) {
      _fired = true;
      widget.onOpen();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: widget.child,
      );
}
