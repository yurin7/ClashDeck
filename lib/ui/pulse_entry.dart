/// Pulse 抽屉占屏宽的比例（左侧面板 80%，右侧露出 20% 概览）。
const double kPulseDrawerWidthFactor = 0.8;

/// 抽屉面板宽度：屏宽的 80%。
double pulseDrawerPanelWidth(double screenWidth) =>
    screenWidth * kPulseDrawerWidthFactor;

/// 把「向右拖的累计位移」映射成 0..1 的展开进度。
///
/// 负一屏在左边：手指从左往右拖，面板从左侧滑出；拖得越远越接近 1，
/// 超过面板宽度后夹住。
double pulseDrawerProgress({
  required double dragDx,
  required double panelWidth,
}) {
  if (panelWidth <= 0) return 0;
  return (dragDx / panelWidth).clamp(0.0, 1.0);
}

/// 松手时是否完成打开：过半或者向右甩得够快。
bool pulseDrawerShouldOpen({
  required double progress,
  required double velocity,
}) => progress > 0.35 || velocity > 300;

/// 面板已打开时，向左拖收起的判定：退回超过 35% 或者向左甩得够快。
bool pulseDrawerShouldClose({
  required double progress,
  required double velocity,
}) => progress < 0.65 || velocity < -300;

/// 概览页向右拖时，累计多少像素才开始拉抽屉（过滤轻微抖动）。
///
/// 起手位置不做限制：第 0 页向右拖会先触发 PageView 的 overscroll，
/// 这里用 overscroll 事件驱动抽屉，不依赖系统边缘手势排除。
const double kPulseOverscrollStartDx = 12;

/// 抽屉滑出后向左回收：只允许减小累计位移，不会变成负值。
///
/// 「半开时向左拖」不应产生任何页面移动，只是把抽屉收回去。
double pulseBackDrag({
  required double dx,
  required double delta,
  required bool active,
}) {
  if (!active || delta >= 0) return dx;
  return (dx + delta).clamp(0.0, double.infinity);
}

/// 抽屉滑出后继续向右拖：累计位移必须继续增长。
///
/// `_beginPulse()` 一触发就会把 `active` 置 true 且 reveal > 0；
/// 如果此时只处理负向 delta，进度会冻在刚越过阈值的那一下，
/// 松手按低进度结算，表现为「只露一条就缩回」。
double pulseForwardDrag({required double dx, required double delta}) {
  if (delta <= 0) return dx;
  return dx + delta;
}
