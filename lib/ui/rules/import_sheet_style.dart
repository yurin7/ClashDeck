import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// 底部导入面板（在线规则集 / GEO 数据）共用的尺寸与外观。
///
/// 两个面板视觉上要像同一个组件家族：同样的最大高度、同样的深底卡片、
/// 同样的标题行按钮热区。
double importSheetMaxHeight(BuildContext context) =>
    math.min(MediaQuery.sizeOf(context).height * 0.82, 560);

/// 面板里「一块内容」的统一卡片：深底 + 圆角 + 细边。
Widget importSheetCard(BuildContext context, {required Widget child}) {
  final scheme = Theme.of(context).colorScheme;
  return Material(
    color: scheme.surfaceContainerLow,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(Radiuses.md),
      side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.6)),
    ),
    clipBehavior: Clip.antiAlias,
    child: child,
  );
}

/// 面板标题行里的文字按钮：统一 44dp 点击热区，避免标题旁边有过小的可点区。
Widget importSheetAction({
  required String label,
  required VoidCallback? onPressed,
}) {
  return TextButton(
    style: TextButton.styleFrom(
      minimumSize: const Size(44, 44),
      padding: const EdgeInsets.symmetric(horizontal: Insets.sm),
    ),
    onPressed: onPressed,
    child: Text(label),
  );
}
