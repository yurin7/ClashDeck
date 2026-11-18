import 'package:material_ui/material_ui.dart';

import '../sheets.dart';

/// 选择类底部弹窗的统一入口（规范「B. 选择类」）。
///
/// 业务代码只调这个函数（或 `EditDialog` / `ConfirmDialog`），
/// 具体尺寸 / 圆角 / 拖拽手柄 / 关闭按钮 / 底部常驻按钮都由 [showAppSheet] 保证：
/// - 高 `min(屏高 * 0.72, 640)`；
/// - 顶部圆角 + 拖拽手柄 + 左标题右关闭；
/// - 内容区可滚、底部按钮不随内容滚走。
Future<T?> showSelectSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder body,
  List<Widget> actions = const <Widget>[],
  bool showClose = true,
}) {
  return showAppSheet<T>(
    context,
    title: title,
    subtitle: subtitle,
    body: body,
    actions: actions,
    showClose: showClose,
  );
}
