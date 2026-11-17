import 'package:material_ui/material_ui.dart';

import 'theme.dart';

// 顶部小胶囊：用于「已切换到 X」「已取消切换」这类一闪而过的确认反馈。
//
// 为什么不复用 `showToast`：底部胶囊会占用底部导航上方的位置，而这类反馈
// 不需要打断操作，放在顶部更不挡手；两者位置不同，用两套 Overlay 互不干扰。

/// 顶部胶囊默认显示时长。
const Duration kTopNoticeDuration = Duration(milliseconds: 1200);

/// 淡入淡出时长。
const Duration kTopNoticeFade = Duration(milliseconds: 180);

class _TopNoticeData {
  const _TopNoticeData({
    required this.message,
    required this.ok,
    required this.total,
  });

  final String message;

  /// true 用成功色 + 勾；false 用中立色（表示「没做成」而不是报错）。
  final bool ok;

  final Duration total;
}

class _TopNoticeController {
  OverlayEntry? _entry;
  final ValueNotifier<_TopNoticeData?> data = ValueNotifier<_TopNoticeData?>(
    null,
  );

  void show(BuildContext context, _TopNoticeData next) {
    final overlay = Overlay.of(context, rootOverlay: true);
    if (_entry == null || !(_entry?.mounted ?? false)) {
      _entry = OverlayEntry(
        builder: (_) => _TopNoticeView(data: data, onDone: hide),
      );
      overlay.insert(_entry!);
    }
    data.value = next;
  }

  void hide() {
    data.value = null;
  }

  void dispose() {
    _entry?.remove();
    _entry = null;
    data.dispose();
  }
}

final _TopNoticeController _notices = _TopNoticeController();

/// 在顶部弹一条胶囊。已有提示时直接换成新的，并重新计时。
void showTopNotice(
  BuildContext context,
  String message, {
  bool ok = true,
  Duration duration = kTopNoticeDuration,
}) {
  _notices.show(
    context,
    _TopNoticeData(message: message, ok: ok, total: duration),
  );
}

/// 立即收起顶部胶囊。
void hideTopNotice() {
  _notices.hide();
}

/// 兜底清理（主要给测试的 tearDown 用）。
void disposeTopNotices() {
  _notices.dispose();
}

class _TopNoticeView extends StatefulWidget {
  const _TopNoticeView({required this.data, required this.onDone});

  final ValueNotifier<_TopNoticeData?> data;
  final VoidCallback onDone;

  @override
  State<_TopNoticeView> createState() => _TopNoticeViewState();
}

/// 和底部胶囊同一套计时手法：一个总时长等于整条生命周期的
/// `AnimationController`，前 [kTopNoticeFade] 淡入、后 [kTopNoticeFade] 淡出，
/// 中间保持，结束由 `onDone` 移除浮层（不留 `Timer`）。
class _TopNoticeViewState extends State<_TopNoticeView>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(
    vsync: this,
    duration: kTopNoticeFade,
  )..addStatusListener(_onStatus);

  _TopNoticeData? _shown;
  Duration _total = kTopNoticeDuration;

  double get _fadeRatio {
    final total = _total.inMilliseconds;
    if (total <= 0) return 0.2;
    return (kTopNoticeFade.inMilliseconds / total).clamp(0.02, 0.45);
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
      _anim.animateTo(1, duration: kTopNoticeFade);
      return;
    }
    setState(() {
      _shown = next;
      _total = next.total;
    });
    _anim.duration = next.total;
    // 新消息从「淡入刚结束」的位置继续跑，避免重复淡入。
    _anim.forward(from: _fadeRatio);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final shown = _shown;
    if (shown == null) return const SizedBox.shrink();

    final accent = shown.ok ? context.semantic.ok : scheme.onSurfaceVariant;

    return Positioned(
      top: MediaQuery.paddingOf(context).top + Insets.md,
      left: Insets.xl,
      right: Insets.xl,
      child: AnimatedBuilder(
        animation: _anim,
        builder: (context, child) {
          final ratio = _fadeRatio;
          final v = _anim.value;
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
                offset: Offset(0, -10 * (1 - eased)),
                child: child,
              ),
            ),
          );
        },
        child: Center(
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.lg,
                vertical: Insets.sm,
              ),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Insets.xl),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    shown.ok ? Icons.check_circle_outline : Icons.info_outline,
                    size: 16,
                    color: accent,
                  ),
                  const SizedBox(width: Insets.sm),
                  Flexible(
                    child: Text(
                      shown.message,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
