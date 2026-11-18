import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import './widgets/app_ink.dart';

export 'app_dialog.dart';
export 'toast.dart';
export 'top_notice.dart';

/// 页面统一的容器：无阴影、1px 细描边、18 圆角。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(Insets.lg),
    this.color,
    this.borderColor,
    this.onTap,
    this.onLongPress,
    this.accent,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final Color? borderColor;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// 左侧 2px 强调条的颜色（用于「当前生效」这类需要一眼看出的卡片）。
  final Color? accent;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final shape = RoundedRectangleBorder(
      borderRadius: const BorderRadius.all(Radiuses.card),
      side: BorderSide(color: borderColor ?? scheme.outlineVariant),
    );
    Widget content = Padding(padding: padding, child: child);
    if (accent != null) {
      content = Stack(
        children: [
          Positioned(
            left: 0,
            top: Insets.md,
            bottom: Insets.md,
            child: Container(
              width: 2,
              decoration: BoxDecoration(
                color: accent,
                borderRadius: BorderRadius.circular(1),
              ),
            ),
          ),
          content,
        ],
      );
    }
    return Material(
      color: color ?? scheme.surfaceContainerLow,
      shape: shape,
      clipBehavior: Clip.antiAlias,
      child: (onTap == null && onLongPress == null)
          ? content
          : AppInkWell(onTap: onTap, onLongPress: onLongPress, child: content),
    );
  }
}

/// 大写宽字距的微标签，用来做分区标题。
class MicroLabel extends StatelessWidget {
  const MicroLabel(this.text, {super.key, this.color, this.trailing});

  final String text;
  final Color? color;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: microStyle(context, color: color ?? scheme.onSurfaceVariant),
        ),
        if (trailing != null) ...[
          const SizedBox(width: Insets.sm),
          const Expanded(child: SizedBox.shrink()),
          trailing!,
        ],
      ],
    );
  }
}

/// 1px 分隔线，带可选左缩进。
class Hairline extends StatelessWidget {
  const Hairline({super.key, this.indent = 0});

  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
    padding: EdgeInsets.only(left: indent),
    child: Divider(height: 1, thickness: 1),
  );
}

/// 分区标题：微标签 + 说明 + 右侧动作。
class SectionTitle extends StatelessWidget {
  const SectionTitle({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.icon,
  });

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        Insets.xs,
        Insets.xl,
        Insets.xs,
        Insets.sm,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: scheme.onSurfaceVariant),
                const SizedBox(width: 6),
              ],
              Expanded(child: MicroLabel(title)),
              ?trailing,
            ],
          ),
          if (subtitle != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(subtitle!, style: hintStyle(context)),
            ),
        ],
      ),
    );
  }
}

/// 小标签：状态、计数、模式这类短信息。
class Pill extends StatelessWidget {
  const Pill({
    super.key,
    required this.label,
    this.color,
    this.icon,
    this.dense = false,
    this.onTap,
    this.filled = false,
  });

  final String label;
  final Color? color;
  final IconData? icon;
  final bool dense;
  final VoidCallback? onTap;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurfaceVariant;
    final bg = filled ? fg : fg.withValues(alpha: 0.12);
    final fgColor = filled
        ? (ThemeData.estimateBrightnessForColor(fg) == Brightness.dark
              ? Colors.white
              : Colors.black)
        : fg;
    final child = Container(
      padding: EdgeInsets.symmetric(
        horizontal: dense ? 6 : 8,
        vertical: dense ? 2 : 3,
      ),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(dense ? 6 : 7),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: dense ? 11 : 12.5, color: fgColor),
            const SizedBox(width: 4),
          ],
          Text(
            label,
            style: display(
              dense ? 10.5 : 11.5,
              weight: 600,
              color: fgColor,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
    if (onTap == null) return child;
    return AppInkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(7),
      child: child,
    );
  }
}

/// 空状态：图标 + 标题 + 说明 + 可选按钮。
class EmptyHint extends StatelessWidget {
  const EmptyHint({
    super.key,
    required this.icon,
    required this.title,
    this.message,
    this.action,
    this.compact = false,
  });

  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: EdgeInsets.symmetric(
        horizontal: Insets.xl,
        vertical: compact ? Insets.md : Insets.xxl,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: compact ? 38 : 58,
            height: compact ? 38 : 58,
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHigh,
              shape: BoxShape.circle,
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: Icon(icon, size: compact ? 18 : 26, color: scheme.primary),
          ),
          SizedBox(height: compact ? Insets.sm : Insets.lg),
          Text(
            title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          if (message != null) ...[
            const SizedBox(height: 6),
            Text(
              message!,
              style: hintStyle(context),
              textAlign: TextAlign.center,
            ),
          ],
          if (action != null) ...[const SizedBox(height: Insets.lg), action!],
        ],
      ),
    );
  }
}

/// 一行元信息（时间、大小、协议数…）。
class MetaRow extends StatelessWidget {
  const MetaRow({super.key, required this.items, this.separator = ' · '});

  final List<String> items;
  final String separator;

  @override
  Widget build(BuildContext context) {
    final dim = Theme.of(context).colorScheme.onSurfaceVariant;
    return Text(
      items.where((e) => e.isNotEmpty).join(separator),
      style: mono(11.5, color: dim),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

/// 大号数值 + 单位 + 微标签，用于速率、延迟、计数。
class StatTile extends StatelessWidget {
  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.color,
    this.alignEnd = false,
    this.compact = false,
  });

  final String label;
  final String value;
  final String? unit;
  final Color? color;
  final bool alignEnd;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final fg = color ?? scheme.onSurface;
    return Column(
      crossAxisAlignment: alignEnd
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(), style: microStyle(context)),
        const SizedBox(height: 6),
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(
              value,
              style: display(
                compact ? 22 : 30,
                weight: 700,
                color: fg,
              ).copyWith(fontFeatures: const [FontFeature.tabularFigures()]),
            ),
            if (unit != null) ...[
              const SizedBox(width: 3),
              Text(
                unit!,
                style: display(12, weight: 500, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// 状态圆点，运行中时带呼吸动画。
class StatusDot extends StatefulWidget {
  const StatusDot({
    super.key,
    required this.color,
    this.size = 8,
    this.pulsing = false,
  });

  final Color color;
  final double size;
  final bool pulsing;

  @override
  State<StatusDot> createState() => _StatusDotState();
}

class _StatusDotState extends State<StatusDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  );

  /// 呼吸用往返曲线：0 → 1 → 0，循环回起点时不会硬跳。
  late final Animation<double> _breath = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOut,
  );

  @override
  void initState() {
    super.initState();
    if (widget.pulsing) _controller.repeat(reverse: true);
  }

  @override
  void didUpdateWidget(covariant StatusDot oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.pulsing && !_controller.isAnimating) {
      _controller.repeat(reverse: true);
    } else if (!widget.pulsing && _controller.isAnimating) {
      _controller.stop();
      _controller.value = 0;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dot = Container(
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulsing) return dot;
    return AnimatedBuilder(
      animation: _breath,
      builder: (context, child) {
        final t = _breath.value;
        final glow = 10 * t;
        // 光晕必须画在圆点尺寸之外、且不参与布局：否则 Stack 会随光晕长大变宽，
        // 把右边那行「RUNNING · 运行中」一路往右推，循环回到 0 时又猛地弹回来。
        return SizedBox(
          width: widget.size,
          height: widget.size,
          child: Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.center,
            children: [
              Positioned(
                left: -glow / 2,
                top: -glow / 2,
                child: Container(
                  width: widget.size + glow,
                  height: widget.size + glow,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.color.withValues(alpha: 0.22 * (1 - t)),
                  ),
                ),
              ),
              child!,
            ],
          ),
        );
      },
      child: dot,
    );
  }
}

/// 主行动按钮：主色渐变，圆角，等宽字距。
class AccentButton extends StatelessWidget {
  const AccentButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.expand = true,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final semantic = context.semantic;
    final enabled = onPressed != null;
    final child = Container(
      height: 46,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: Insets.xl),
      decoration: BoxDecoration(
        gradient: enabled
            ? LinearGradient(
                colors: semantic.accentGradient,
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
              )
            : null,
        color: enabled
            ? null
            : Theme.of(context).colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radiuses.md),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(
              icon,
              size: 17,
              color: enabled
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: Insets.sm),
          ],
          Text(
            label,
            style: display(
              14,
              weight: 700,
              color: enabled
                  ? Colors.white
                  : Theme.of(context).colorScheme.onSurfaceVariant,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
    return SizedBox(
      width: expand ? double.infinity : null,
      child: Material(
        color: Colors.transparent,
        child: AppInkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(Radiuses.md),
          child: child,
        ),
      ),
    );
  }
}

/// 流量迷你曲线：一条渐变面积 + 折线。
class Sparkline extends StatelessWidget {
  const Sparkline({
    super.key,
    required this.values,
    this.color,
    this.height = 56,
  });

  final List<double> values;
  final Color? color;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final c = color ?? scheme.primary;
    return SizedBox(
      height: height,
      width: double.infinity,
      child: CustomPaint(
        painter: _SparkPainter(
          values: values,
          stroke: c,
          fill: c.withValues(alpha: 0.16),
          hairline: scheme.outlineVariant,
        ),
      ),
    );
  }
}

class _SparkPainter extends CustomPainter {
  _SparkPainter({
    required this.values,
    required this.stroke,
    required this.fill,
    required this.hairline,
  });

  final List<double> values;
  final Color stroke;
  final Color fill;
  final Color hairline;

  @override
  void paint(Canvas canvas, Size size) {
    // 底线
    final line = Paint()
      ..color = hairline
      ..strokeWidth = 1;
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      line,
    );
    if (values.length < 2) return;

    final maxValue = values.reduce(math.max);
    final peak = maxValue <= 0 ? 1.0 : maxValue;
    final stepX = size.width / (values.length - 1);
    final points = <Offset>[
      for (var i = 0; i < values.length; i++)
        Offset(
          i * stepX,
          size.height - (values[i] / peak) * (size.height - 6) - 2,
        ),
    ];

    final area = Path()..moveTo(points.first.dx, size.height);
    for (final p in points) {
      area.lineTo(p.dx, p.dy);
    }
    area
      ..lineTo(points.last.dx, size.height)
      ..close();
    canvas.drawPath(area, Paint()..color = fill);

    final strokePath = Path()..moveTo(points.first.dx, points.first.dy);
    for (var i = 1; i < points.length; i++) {
      final prev = points[i - 1];
      final curr = points[i];
      final midX = (prev.dx + curr.dx) / 2;
      strokePath.cubicTo(midX, prev.dy, midX, curr.dy, curr.dx, curr.dy);
    }
    canvas.drawPath(
      strokePath,
      Paint()
        ..color = stroke
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6
        ..strokeJoin = StrokeJoin.round
        ..strokeCap = StrokeCap.round,
    );

    canvas.drawCircle(points.last, 2.4, Paint()..color = stroke);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter oldDelegate) =>
      oldDelegate.values != values ||
      oldDelegate.stroke != stroke ||
      oldDelegate.fill != fill;
}

/// 对话框关闭后，控件树在退场动画里还会短暂引用控制器；此刻直接 `dispose()`
/// 会撞 `_dependents.isEmpty` 断言（Flutter 3.50 的 `TextEditingController`）。
/// 这个帮助函数把释放推迟到动画结束之后。
void disposeAfterDialog(ChangeNotifier notifier) {
  Future<void>.delayed(const Duration(milliseconds: 600), notifier.dispose);
}

/// iOS 式的左滑操作行：手指从右往左拖，露出右侧操作按钮。
///
/// 拖动过程跟手，松手按位移/速度判断停在展开态还是弹回；展开状态由外部
/// 持有（一次只允许一行展开）。行内容展开时对应区域改由本组件接管点击，
/// 点一下即收起，不会误触发行本身的「设为运行配置」。
class SlidableRow extends StatefulWidget {
  const SlidableRow({
    super.key,
    required this.child,
    required this.actionLabel,
    required this.onAction,
    this.open = false,
    this.onOpenChanged,
    this.actionWidth = 80,
  });

  final Widget child;

  /// 右侧按钮文案，例如「删除」。
  final String actionLabel;
  final VoidCallback onAction;

  /// 是否处于展开态（由外部单一来源控制）。
  final bool open;
  final ValueChanged<bool>? onOpenChanged;
  final double actionWidth;

  @override
  State<SlidableRow> createState() => _SlidableRowState();
}

class _SlidableRowState extends State<SlidableRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
    value: widget.open ? 1 : 0,
  );

  @override
  void didUpdateWidget(covariant SlidableRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.open != oldWidget.open) {
      _controller.animateTo(widget.open ? 1 : 0, curve: Curves.easeOutCubic);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onDragUpdate(DragUpdateDetails details) {
    _controller.value =
        (_controller.value - details.delta.dx / widget.actionWidth).clamp(
          0.0,
          1.0,
        );
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    final shouldOpen =
        velocity < -220 || (velocity <= 220 && _controller.value > 0.4);
    widget.onOpenChanged?.call(shouldOpen);
    _controller.animateTo(shouldOpen ? 1 : 0, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onHorizontalDragStart: (_) => _controller.stop(),
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: ClipRect(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final value = _controller.value;
            return Stack(
              children: [
                if (value > 0)
                  Positioned.fill(
                    child: Align(
                      alignment: Alignment.centerRight,
                      child: SizedBox(
                        width: widget.actionWidth,
                        child: Material(
                          color: scheme.error,
                          child: AppInkWell(
                            onTap: widget.onAction,
                            child: Center(
                              child: Text(
                                widget.actionLabel,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: scheme.onError,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                Transform.translate(
                  offset: Offset(-value * widget.actionWidth, 0),
                  child: child,
                ),
                if (value > 0)
                  Positioned(
                    left: 0,
                    right: widget.actionWidth * value,
                    top: 0,
                    bottom: 0,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => widget.onOpenChanged?.call(false),
                    ),
                  ),
              ],
            );
          },
          child: ColoredBox(
            color: scheme.surfaceContainerLow,
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
