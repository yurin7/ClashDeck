import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// Pointer-following light and depth for Windows controls.
class DesktopHover extends StatefulWidget {
  const DesktopHover({
    super.key,
    required this.borderRadius,
    required this.child,
    this.color,
    this.enabled = true,
    this.intensity = 1,
    this.lift = 0,
    this.tilt = 0,
  });

  final BorderRadius borderRadius;
  final Widget child;
  final Color? color;
  final bool enabled;
  final double intensity;
  final double lift;
  final double tilt;

  @override
  State<DesktopHover> createState() => _DesktopHoverState();
}

class _DesktopHoverState extends State<DesktopHover> {
  final _pointer = ValueNotifier<Alignment>(Alignment.center);
  bool _hovered = false;

  void _trackPointer(Offset position) {
    final size = context.size;
    if (size == null || size.isEmpty) return;
    _pointer.value = Alignment(
      (2 * position.dx / size.width - 1).clamp(-1.0, 1.0),
      (2 * position.dy / size.height - 1).clamp(-1.0, 1.0),
    );
  }

  @override
  void dispose() {
    _pointer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final motion = Motion.of(context);
    final primary = Theme.of(context).colorScheme.primary;
    final lift = motion.reduceMotion ? 0.0 : widget.lift;
    final tilt = motion.reduceMotion ? 0.0 : widget.tilt;
    return MouseRegion(
      onEnter: (event) {
        if (!motion.reduceMotion) _trackPointer(event.localPosition);
        setState(() => _hovered = true);
      },
      onHover: (event) {
        if (widget.enabled && !motion.reduceMotion) {
          _trackPointer(event.localPosition);
        }
      },
      onExit: (_) => setState(() => _hovered = false),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.enabled && _hovered ? 1 : 0),
        duration: motion.reduceMotion ? Duration.zero : motion.fast,
        curve: motion.enter,
        child: widget.tilt == 0
            ? widget.child
            : RepaintBoundary(child: widget.child),
        builder: (context, progress, child) =>
            ValueListenableBuilder<Alignment>(
              valueListenable: _pointer,
              builder: (context, position, surface) => Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.0012)
                  ..rotateX(-position.y * tilt * progress)
                  ..rotateY(position.x * tilt * progress)
                  ..setTranslationRaw(0, -lift * progress, 0),
                transformHitTests: false,
                child: surface,
              ),
              child: Stack(
                fit: StackFit.passthrough,
                clipBehavior: Clip.none,
                children: [
                  if (lift > 0 && progress > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            borderRadius: widget.borderRadius,
                            boxShadow: [
                              BoxShadow(
                                color: primary.withValues(
                                  alpha: 0.28 * progress,
                                ),
                                blurRadius: 20,
                                offset: const Offset(0, 4),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  KeyedSubtree(key: const ValueKey('surface'), child: child!),
                  if (progress > 0)
                    Positioned.fill(
                      child: IgnorePointer(
                        child: RepaintBoundary(
                          child: CustomPaint(
                            painter: _HoverLight(
                              pointer: motion.reduceMotion ? null : _pointer,
                              borderRadius: widget.borderRadius,
                              color: widget.color ?? primary,
                              level: widget.intensity * progress,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
      ),
    );
  }
}

class _HoverLight extends CustomPainter {
  _HoverLight({
    required this.pointer,
    required this.borderRadius,
    required this.color,
    required this.level,
  }) : super(repaint: pointer);

  final ValueListenable<Alignment>? pointer;
  final BorderRadius borderRadius;
  final Color color;
  final double level;

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final bounds = Offset.zero & size;
    final spot = Rect.fromCircle(
      center: pointer?.value.alongSize(size) ?? bounds.center,
      radius: size.height * 2,
    );
    final transparent = color.withValues(alpha: 0);
    canvas.drawRRect(
      borderRadius.toRRect(bounds),
      Paint()
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: 0.14 * level),
            transparent,
          ],
        ).createShader(spot),
    );
    canvas.drawRRect(
      borderRadius.toRRect(bounds).deflate(0.75),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5
        ..shader = RadialGradient(
          colors: [
            color.withValues(alpha: (0.52 * level).clamp(0, 1).toDouble()),
            color.withValues(alpha: 0.16 * level),
            transparent,
          ],
          stops: const [0, 0.56, 1],
        ).createShader(spot),
    );
  }

  @override
  bool shouldRepaint(covariant _HoverLight oldDelegate) =>
      oldDelegate.pointer != pointer ||
      oldDelegate.borderRadius != borderRadius ||
      oldDelegate.color != color ||
      oldDelegate.level != level;
}
