import 'package:material_ui/material_ui.dart';

import '../pulse_entry.dart';
import '../theme.dart';

/// 概览页右缘的「拉出 Pulse」提示把手。
///
/// 只是一块可见但低调的竖条 + 小箭头：真正的手势由外面 28dp 宽的
/// `HorizontalDragArea` 接管，用户从屏幕右缘往左滑即可拉出抽屉。
class PulseEdgeHandle extends StatelessWidget {
  const PulseEdgeHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Align(
      alignment: Alignment.centerRight,
      child: Container(
        width: kPulseEdgeHandleWidth,
        height: 72,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.6),
          borderRadius: const BorderRadius.horizontal(
            left: Radius.circular(Radiuses.lg),
          ),
          border: Border(
            left: BorderSide(
              color: scheme.outlineVariant.withValues(alpha: 0.7),
            ),
          ),
        ),
        child: Icon(
          Icons.chevron_left_rounded,
          size: 16,
          color: scheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
