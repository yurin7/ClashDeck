import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

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
      color: Colors.transparent,
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
  }) => SizedBox(
    width: _buttonWidth,
    height: desktopCaptionHeight - 7,
    child: IconButton(
      onPressed: onPressed,
      tooltip: tooltip,
      icon: Icon(icon, size: 16),
      style: IconButton.styleFrom(
        padding: EdgeInsets.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
        hoverColor: error?.withValues(alpha: 0.2),
      ),
    ),
  );
}
