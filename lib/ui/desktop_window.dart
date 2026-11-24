import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'desktop_hover.dart';
import 'motion.dart';

const desktopCaptionHeight = 36.0;
const _buttonWidth = 44.0;
const _windowChannel = MethodChannel('dev.clashdeck/windows-window');

Future<void> closeDesktopWindow() => _windowChannel.invokeMethod<void>('close');

class DesktopWindowFrame extends StatelessWidget {
  const DesktopWindowFrame({super.key, this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) => Overlay.wrap(
    // The caption sits above the Navigator, so its tooltips need their own host.
    child: Stack(
      fit: StackFit.expand,
      children: [
        ?child,
        const Positioned(top: 0, right: 0, child: DesktopWindowCaption()),
      ],
    ),
  );
}

class DesktopWindowCaption extends StatefulWidget {
  const DesktopWindowCaption({super.key});

  @override
  State<DesktopWindowCaption> createState() => _DesktopWindowCaptionState();
}

class _DesktopWindowCaptionState extends State<DesktopWindowCaption> {
  bool _maximized = false;

  @override
  void initState() {
    super.initState();
    _windowChannel.setMethodCallHandler((call) async {
      if (call.method == 'maximized' && call.arguments is bool) {
        setState(() => _maximized = call.arguments as bool);
      }
    });
  }

  @override
  void dispose() {
    _windowChannel.setMethodCallHandler(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Padding(
        padding: const EdgeInsets.only(top: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _button(
              '最小化',
              Icons.remove,
              () => _windowChannel.invokeMethod<void>('minimize'),
            ),
            _button(
              _maximized ? '还原窗口' : '最大化',
              _maximized ? Icons.filter_none : Icons.crop_square,
              () => _windowChannel.invokeMethod<void>('toggleMaximize'),
            ),
            _button(
              '关闭窗口',
              Icons.close,
              closeDesktopWindow,
              error: colors.error,
            ),
          ],
        ),
      ),
    );
  }

  Widget _button(
    String tooltip,
    IconData icon,
    VoidCallback onPressed, {
    Color? error,
  }) {
    final colors = Theme.of(context).colorScheme;
    final tint = error ?? colors.primary;
    final motion = Motion.of(context);
    final duration = motion.reduceMotion ? Duration.zero : motion.fast;
    final radius = BorderRadius.circular(6);
    return SizedBox(
      width: _buttonWidth,
      height: desktopCaptionHeight - 7,
      child: DesktopHover(
        borderRadius: radius,
        color: tint,
        intensity: 1.2,
        child: IconButton(
          onPressed: onPressed,
          tooltip: tooltip,
          icon: AnimatedSwitcher(
            duration: duration,
            switchInCurve: motion.enter,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: ScaleTransition(
                scale: animation.drive(Tween(begin: 0.7, end: 1.0)),
                child: child,
              ),
            ),
            child: Icon(icon, key: ValueKey(icon), size: 15),
          ),
          style: ButtonStyle(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.hovered)
                  ? error ?? colors.onSurface
                  : colors.onSurfaceVariant;
            }),
            overlayColor: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.pressed)
                  ? tint.withValues(alpha: 0.25)
                  : Colors.transparent;
            }),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(borderRadius: radius),
            ),
            side: WidgetStateProperty.resolveWith((states) {
              return states.contains(WidgetState.focused)
                  ? BorderSide(color: tint.withValues(alpha: 0.65))
                  : BorderSide.none;
            }),
            splashFactory: NoSplash.splashFactory,
            animationDuration: duration,
          ),
        ),
      ),
    );
  }
}
