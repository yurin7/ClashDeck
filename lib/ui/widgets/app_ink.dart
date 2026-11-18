import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// 统一的点击反馈：去掉 Material 默认的水波纹与残留高亮。
///
/// 安卓上 [InkWell] 的 splash/highlight 会留在原地（尤其是浮层里的选项行，
/// 收起后再打开还能看到一圈底色），和这套深色界面很不搭。这里全部关掉，
/// 改成 120ms 的轻微缩放反馈，按下即回弹。
class AppInkWell extends StatefulWidget {
  const AppInkWell({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.onDoubleTap,
    this.onTapCancel,
    this.onTapDown,
    this.borderRadius,
    this.customBorder,
    this.canRequestFocus = true,
    this.excludeFromSemantics = false,
    this.autofocus = false,
    this.focusNode,
    this.enableFeedback = false,
    this.hoverColor,
    this.focusColor,
    this.splashColor,
    this.highlightColor,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final VoidCallback? onDoubleTap;
  final VoidCallback? onTapCancel;
  final ValueChanged<TapDownDetails>? onTapDown;
  final BorderRadius? borderRadius;
  final ShapeBorder? customBorder;
  final bool canRequestFocus;
  final bool excludeFromSemantics;
  final bool autofocus;
  final FocusNode? focusNode;
  final bool enableFeedback;
  final Color? hoverColor;
  final Color? focusColor;
  final Color? splashColor;
  final Color? highlightColor;

  @override
  State<AppInkWell> createState() => _AppInkWellState();
}

class _AppInkWellState extends State<AppInkWell> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed == value) return;
    setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius ?? BorderRadius.all(Radiuses.chip);
    // 没有点击回调时不要建 InkWell：空的 InkWell 仍会注册 tap 手势，
    // 把落在子内容（例如 SelectableTile 里的 NameChip）上的点击吞掉。
    final interactive =
        widget.onTap != null ||
        widget.onLongPress != null ||
        widget.onDoubleTap != null ||
        widget.onTapDown != null ||
        widget.onTapCancel != null;

    final child = interactive
        ? AnimatedScale(
            scale: _pressed ? 0.985 : 1,
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOutCubic,
            child: Material(
              type: MaterialType.transparency,
              child: InkWell(
                onTap: widget.onTap,
                onLongPress: widget.onLongPress,
                onDoubleTap: widget.onDoubleTap,
                onTapCancel: () {
                  _setPressed(false);
                  widget.onTapCancel?.call();
                },
                onTapDown: (details) {
                  _setPressed(true);
                  widget.onTapDown?.call(details);
                },
                onTapUp: (_) => _setPressed(false),
                borderRadius: radius,
                customBorder: widget.customBorder,
                canRequestFocus: widget.canRequestFocus,
                excludeFromSemantics: widget.excludeFromSemantics,
                autofocus: false,
                enableFeedback: widget.enableFeedback,
                hoverColor: widget.hoverColor ?? Colors.transparent,
                focusColor: widget.focusColor ?? Colors.transparent,
                splashColor: widget.splashColor ?? Colors.transparent,
                highlightColor: widget.highlightColor ?? Colors.transparent,
                overlayColor: const WidgetStatePropertyAll(Colors.transparent),
                splashFactory: NoSplash.splashFactory,
                child: widget.child,
              ),
            ),
          )
        : widget.child;

    return Focus(
      canRequestFocus: widget.canRequestFocus,
      autofocus: widget.autofocus,
      focusNode: widget.focusNode,
      child: child,
    );
  }
}

/// 浮层里的一行可点内容：去掉水波纹，只保留按下反馈。
///
/// [Material] 的尺寸在这里不重要（外层已有背景），所以直接用透明材质。
class AppInkSurface extends StatelessWidget {
  const AppInkSurface({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius,
    this.color,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius? borderRadius;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final radius = borderRadius ?? BorderRadius.all(Radiuses.chip);
    return Material(
      color: color ?? Colors.transparent,
      borderRadius: radius,
      clipBehavior: Clip.antiAlias,
      child: AppInkWell(onTap: onTap, borderRadius: radius, child: child),
    );
  }
}
