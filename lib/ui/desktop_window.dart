import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'motion.dart';

const desktopCaptionHeight = 36.0;
const _buttonWidth = 44.0;
const _windowChannel = MethodChannel('dev.clashdeck/windows-window');

Future<void> closeDesktopWindow() => _windowChannel.invokeMethod<void>('close');

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
    return SizedBox(
      width: _buttonWidth,
      height: desktopCaptionHeight - 7,
      child: IconButton(
        onPressed: onPressed,
        tooltip: tooltip,
        icon: Icon(icon, size: 15),
        style: ButtonStyle(
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.hovered)
                ? error ?? colors.onSurface
                : colors.onSurfaceVariant;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) {
              return tint.withValues(alpha: 0.25);
            }
            if (states.contains(WidgetState.hovered)) {
              return tint.withValues(alpha: 0.13);
            }
            return Colors.transparent;
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          side: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.focused)
                ? BorderSide(color: tint.withValues(alpha: 0.65))
                : BorderSide.none;
          }),
          splashFactory: NoSplash.splashFactory,
          animationDuration: Motion.of(context).fast,
        ),
      ),
    );
  }
}
