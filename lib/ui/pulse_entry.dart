/// Pulse 抽屉占屏宽的比例（右侧面板 80%，左侧露出 20% 概览）。
const double kPulseDrawerWidthFactor = 0.8;

/// 抽屉面板宽度：屏宽的 80%。
double pulseDrawerPanelWidth(double screenWidth) =>
    screenWidth * kPulseDrawerWidthFactor;

/// 把「向左拖的累计位移」映射成 0..1 的展开进度。
///
/// 只在左滑打开时使用：拖得越远越接近 1，超过面板宽度后夹住。
double pulseDrawerProgress({
  required double dragDx,
  required double panelWidth,
}) {
  if (panelWidth <= 0) return 0;
  return (-dragDx / panelWidth).clamp(0.0, 1.0);
}

/// 松手时是否完成打开：过半或者向左甩得够快。
bool pulseDrawerShouldOpen({
  required double progress,
  required double velocity,
}) => progress > 0.35 || velocity < -300;

/// 面板已打开时，向右拖收起的判定：退回超过 35% 或者向右甩得够快。
bool pulseDrawerShouldClose({
  required double progress,
  required double velocity,
}) => progress < 0.65 || velocity > 300;

/// 概览页右缘的透明手势带宽度（从屏幕右缘往左算）。
///
/// 只有起手落在这条带子里才驱动抽屉；屏幕中部的左右滑仍然交给
/// PageView 翻页，两者不再抢手势。
const double kPulseEdgeBandWidth = 28;

/// 右缘把手宽度：可见但低调，提示用户「这里可以往左滑」。
const double kPulseEdgeHandleWidth = 24;

/// 起手点是否落在右缘手势带内。
bool pulseEdgeDragStarts({
  required double startX,
  required double screenWidth,
}) {
  if (screenWidth <= 0) return false;
  return startX >= screenWidth - kPulseEdgeBandWidth;
}
