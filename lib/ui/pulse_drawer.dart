import 'package:material_ui/material_ui.dart';

import 'pulse_entry.dart';
import 'theme.dart';

/// Pulse 左侧遮罩层：面板占屏宽 80%、贴左侧，右侧 20% 露出压暗的概览。
///
/// 只负责几何与遮罩，进度由外部（`AppShell` 的拖拽/动画）驱动，
/// 这样手势跟手、回弹和关闭都能共用同一条 progress 时间轴。
class PulseDrawer extends StatelessWidget {
  const PulseDrawer({
    super.key,
    required this.progress,
    required this.onClose,
    required this.child,
  });

  /// 0 = 完全收起，1 = 完全展开。
  final double progress;

  /// 点右侧暗区时收起。
  final VoidCallback onClose;

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final panelWidth = pulseDrawerPanelWidth(width);
        final p = progress.clamp(0.0, 1.0);
        final left = panelWidth * p - panelWidth;
        final maskLeft = panelWidth * p;
        return Stack(
          children: [
            // 右侧暗区：面板滑入时同步加深，点一下收起。
            if (maskLeft < width - 0.5)
              Positioned(
                left: maskLeft,
                right: 0,
                top: 0,
                bottom: 0,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClose,
                  child: ColoredBox(
                    color: Colors.black.withValues(alpha: 0.45 * p),
                  ),
                ),
              ),
            // 抽屉面板：左侧贴边直角，右侧圆角。
            Positioned(
              left: left,
              top: 0,
              bottom: 0,
              width: panelWidth,
              child: ClipRRect(
                borderRadius: const BorderRadius.horizontal(
                  right: Radius.circular(Radiuses.lg),
                ),
                child: Material(color: const Color(0xFF05060A), child: child),
              ),
            ),
          ],
        );
      },
    );
  }
}
