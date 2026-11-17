import 'dart:async';

import 'package:material_ui/material_ui.dart';

import 'theme.dart';

// 底部悬浮胶囊提示（toast）。
//
// 为什么不用 `SnackBar`：它挂在 `Scaffold` 底部，会盖住本 App 自己画的
// 底部三个主按钮；也没法做到「点一下立刻消失」和「新消息合并到同一条」。
//
// 这里的实现：一个 `OverlayEntry` + 单实例 `ValueNotifier`，位置固定在
// 下面这个 clearance 之上，永远不碰底栏。

/// 胶囊底边离屏幕底部的距离。
///
/// 66 = 底部岛屿高度，20 = 岛屿与屏幕底部的间距，10 = 再留一点呼吸。
const double kBottomBarClearance = 96;

/// 出现 / 消失的时长（灵动一点：向上弹出、向下收回）。
const Duration kToastFade = Duration(milliseconds: 260);

/// 点掉时的收回时长，比自然消失更快一点，别让用户觉得「点了没反应」。
const Duration kToastDismissFade = Duration(milliseconds: 180);

/// 一条提示的内容。
class _ToastData {
  const _ToastData({
    required this.message,
    required this.total,
    this.actionLabel,
    this.onAction,
  });

  final String message;

  /// 整条提示从出现到消失的时长（含淡入淡出）。
  final Duration total;

  final String? actionLabel;
  final VoidCallback? onAction;
}

/// 全局单例：同一时刻只存在一条提示。
class _ToastController {
  OverlayEntry? _entry;
  final ValueNotifier<_ToastData?> data = ValueNotifier<_ToastData?>(null);

  void show(BuildContext context, _ToastData next) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (_entry == null || !(_entry?.mounted ?? false)) {
      _entry = OverlayEntry(
        builder: (_) => _ToastView(data: data, onDone: hide),
      );
      overlay.insert(_entry!);
    }
    data.value = next;
  }

  /// 收起当前提示（淡出后移除浮层）。
  void hide() {
    data.value = null;
  }

  void dispose() {
    _entry?.remove();
    _entry = null;
    data.dispose();
  }
}

final _ToastController _toasts = _ToastController();

/// 弹一条提示。已有提示时直接换成新的，并重新计时。
void showToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(milliseconds: 2600),
  String? actionLabel,
  VoidCallback? onAction,
}) {
  _toasts.show(
    context,
    _ToastData(
      message: message,
      total: duration,
      actionLabel: actionLabel,
      onAction: onAction,
    ),
  );
}

/// 立即收起当前提示。
void hideToast() {
  _toasts.hide();
}

/// 兜底清理（主要给测试的 tearDown 用）。
void disposeToasts() {
  _toasts.dispose();
}

/// 浮层里真正画出来的胶囊。
///
/// 计时不用 `Timer`，而是用一个总时长等于「整条提示生命周期」的
/// `AnimationController`：前 [kToastFade] 淡入、后 [kToastFade] 淡出，
/// 中间保持。这样测试结束时不会留下待触发的定时器。
class _ToastView extends StatefulWidget {
  const _ToastView({required this.data, required this.onDone});

  final ValueNotifier<_ToastData?> data;
  final VoidCallback onDone;

  @override
  State<_ToastView> createState() => _ToastViewState();
}

class _ToastViewState extends State<_ToastView> with TickerProviderStateMixin {
  /// 管出现 / 消失：0 = 完全收起，1 = 完全展开。
  late final AnimationController _vis = AnimationController(
    vsync: this,
    duration: kToastFade,
    reverseDuration: kToastDismissFade,
  )..addStatusListener(_onStatus);

  /// 管停留：跑完就自然收回。
  late final AnimationController _life = AnimationController(vsync: this)
    ..addStatusListener(_onLifeStatus);

  /// 收回时 `data` 已经是 null，但还要把上一条画完。
  _ToastData? _shown;

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.dismissed) widget.onDone();
  }

  void _onLifeStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) _hide();
  }

  @override
  void initState() {
    super.initState();
    widget.data.addListener(_sync);
    _sync();
  }

  @override
  void dispose() {
    widget.data.removeListener(_sync);
    _vis.dispose();
    _life.dispose();
    super.dispose();
  }

  /// 收回：先反向播出现动画，播完由 [_onStatus] 移除浮层。
  void _hide() {
    if (_vis.status == AnimationStatus.dismissed) return;
    _life.stop();
    _vis.reverse();
  }

  void _sync() {
    final next = widget.data.value;
    if (next == null) {
      _hide();
      return;
    }
    setState(() {
      _shown = next;
    });
    // 新消息覆盖旧消息时，重新计时停留，出现动画从头播（灵动地上弹）。
    _vis.duration = kToastFade;
    unawaited(_vis.forward(from: 0));
    _life
      ..stop()
      ..duration = next.total
      ..forward(from: 0);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();

    return Positioned(
      left: Insets.xl,
      right: Insets.xl,
      bottom: kBottomBarClearance,
      child: AnimatedBuilder(
        animation: Listenable.merge([_vis, _life]),
        builder: (context, child) {
          final t = _vis.value.clamp(0.0, 1.0);
          // 出现用 easeOutBack（略微过冲，显得灵动），收回用 easeInCubic。
          final eased = _vis.status == AnimationStatus.reverse
              ? Curves.easeInCubic.transform(t)
              : Curves.easeOutBack.transform(t);
          final opacity = _vis.status == AnimationStatus.reverse
              ? t
              : Curves.easeOut.transform(t);
          return IgnorePointer(
            ignoring: t == 0,
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: Transform.translate(
                offset: Offset(0, 28 * (1 - eased)),
                child: Transform.scale(
                  scale: 0.94 + 0.06 * eased,
                  child: child,
                ),
              ),
            ),
          );
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: hideToast,
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.md,
                Insets.lg,
                Insets.md,
              ),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Insets.xl),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      shown.message,
                      style: theme.textTheme.bodyMedium,
                    ),
                  ),
                  if (shown.actionLabel != null) ...[
                    const SizedBox(width: Insets.md),
                    TextButton(
                      onPressed: () {
                        hideToast();
                        shown.onAction?.call();
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: Insets.sm,
                        ),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(shown.actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
