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

/// 淡入淡出的时长。
const Duration kToastFade = Duration(milliseconds: 200);

/// 点掉时加速淡出，别让用户觉得「点了没反应」。
const Duration kToastDismissFade = Duration(milliseconds: 120);

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

class _ToastViewState extends State<_ToastView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: kToastFade,
  )..addStatusListener(_onStatus);

  /// 淡出时 `data` 已经是 null，但还要把上一条画完。
  _ToastData? _shown;

  /// 整条提示的总时长，用来把 [kToastFade] 折算成动画里的比例。
  Duration _total = const Duration(milliseconds: 2600);

  double get _fadeRatio {
    final total = _total.inMilliseconds;
    if (total <= 0) return 0.2;
    return (kToastFade.inMilliseconds / total).clamp(0.02, 0.4);
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) widget.onDone();
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
    _anim.dispose();
    super.dispose();
  }

  void _sync() {
    final next = widget.data.value;
    if (next == null) {
      // 点掉或超时：快速淡出，结束后由 onDone 移除浮层。
      _anim.animateTo(1, duration: kToastDismissFade);
      return;
    }
    setState(() {
      _shown = next;
      _total = next.total;
    });
    _anim.duration = next.total;
    // 从淡入结束的位置开始跑，新消息无需再淡入一次。
    _anim.forward(from: _fadeRatio);
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
        animation: _anim,
        builder: (context, child) {
          final ratio = _fadeRatio;
          final v = _anim.value;
          // 0→fadeIn 淡入，1-fadeIn→1 淡出，中间恒为 1。
          final t = v < ratio
              ? (v / ratio).clamp(0.0, 1.0)
              : v > 1 - ratio
              ? ((1 - v) / ratio).clamp(0.0, 1.0)
              : 1.0;
          final eased = Curves.easeOutCubic.transform(t);
          return IgnorePointer(
            ignoring: eased == 0,
            child: Opacity(
              opacity: eased,
              child: Transform.translate(
                offset: Offset(0, 12 * (1 - eased)),
                child: child,
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
