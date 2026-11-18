import 'package:material_ui/material_ui.dart';

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

/// PageView 的滚动物理：概览页（第 0 页）固定关闭横向滚动，
/// 否则左滑会被 PageView 的手势竞技场吃掉，抽屉永远打不开。
/// 配置页 / 设置页保留左右滑。
ScrollPhysics pulsePagerPhysics(int index) => index == 0
    ? const NeverScrollableScrollPhysics()
    : const PageScrollPhysics();
