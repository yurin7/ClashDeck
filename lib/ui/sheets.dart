import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'app_dialog.dart';
import 'theme.dart';

/// 底部 sheet 的统一最大高度：屏高的 72%，最多 640。
///
/// 小屏上按比例缩，大屏上封顶，避免平板上弹窗被拉得过高。
double sheetMaxHeight(BuildContext context) =>
    math.min(MediaQuery.sizeOf(context).height * 0.72, 640);

/// 统一的底部上滑面板。
///
/// 约定：
/// - `isScrollControlled` + 拖拽手柄 + [sheetMaxHeight] 上限，内容超出时内部滚动；
/// - 有 [title] 时渲染固定标题行，右侧「关闭」；菜单型 sheet 不传 title，就没有标题行；
/// - [actions] 常驻在底部，不随内容滚走；
/// - 键盘弹出时整块上移（叠加 `viewInsets.bottom`），搜索框不会被挡住。
Future<T?> showAppSheet<T>(
  BuildContext context, {
  String? title,
  String? subtitle,
  Widget? header,
  required WidgetBuilder body,
  List<Widget> actions = const <Widget>[],
  bool showClose = true,
}) {
  Widget content(BuildContext ctx, {double top = 0}) => Padding(
    padding: EdgeInsets.fromLTRB(Insets.xl, top, Insets.xl, Insets.lg),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (title != null || header != null)
          Padding(
            padding: const EdgeInsets.only(bottom: Insets.sm),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: display(17, weight: 700),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (subtitle != null) ...[
                          const SizedBox(height: 2),
                          Text(subtitle, style: hintStyle(ctx)),
                        ],
                      ],
                    ),
                  )
                else
                  const Spacer(),
                if (showClose)
                  IconButton(
                    tooltip: '关闭',
                    visualDensity: VisualDensity.compact,
                    onPressed: () => Navigator.of(ctx).pop(),
                    icon: const Icon(Icons.close, size: 20),
                  ),
              ],
            ),
          ),
        ?header,
        Flexible(child: body(ctx)),
        if (actions.isNotEmpty) ...[
          const SizedBox(height: Insets.sm),
          Row(children: actions),
        ],
      ],
    ),
  );

  if (Theme.of(context).platform == TargetPlatform.windows) {
    return showAppDialog<T>(
      context,
      width: math.min(580, MediaQuery.sizeOf(context).width - 48),
      builder: (ctx) => Material(
        color: Theme.of(ctx).colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(Radiuses.md),
        clipBehavior: Clip.antiAlias,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: sheetMaxHeight(ctx)),
          child: content(ctx, top: Insets.lg),
        ),
      ),
    );
  }
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    constraints: BoxConstraints(maxHeight: sheetMaxHeight(context)),
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SafeArea(top: false, child: content(ctx)),
    ),
  );
}
