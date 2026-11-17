import 'package:material_ui/material_ui.dart';

import 'theme.dart';

/// 下拉菜单里的一项。
class DropdownOption<T> {
  const DropdownOption(this.value, this.label, {this.subtitle});

  final T value;
  final String label;
  final String? subtitle;
}

/// 统一风格的下拉选择。
///
/// 项目里原本各处混用原生 `DropdownButton` / `DropdownButtonFormField`：底色有灰有
/// 淡紫、弹出层是系统默认样式。这里自己画一层，保证三态一致：
/// 收起时是一行「值 + 箭头」，展开后是贴在控件下方的浮层，选中项用主题淡紫打底，
/// 悬停/按下走 `InkWell` 的 ripple。
///
/// 两种形态：
/// - 表单形态（默认）：带标签的输入框外观，和 `TextField` 对齐；
/// - 紧凑形态（`compact: true`）：只显示当前值 + 箭头，用于设置页右侧。
class AppDropdown<T> extends StatefulWidget {
  const AppDropdown({
    super.key,
    required this.value,
    required this.options,
    required this.onChanged,
    this.label,
    this.helper,
    this.icon,
    this.compact = false,
    this.expand = false,
    this.enabled = true,
  });

  final T value;
  final List<DropdownOption<T>> options;
  final ValueChanged<T> onChanged;

  /// 表单形态下的浮动标签。
  final String? label;
  final String? helper;
  final IconData? icon;

  /// 紧凑形态：无边框，只显示值 + 箭头。
  final bool compact;

  /// 表单形态下是否撑满宽度。
  final bool expand;

  final bool enabled;

  @override
  State<AppDropdown<T>> createState() => _AppDropdownState<T>();
}

class _AppDropdownState<T> extends State<AppDropdown<T>> {
  final OverlayPortalController _portal = OverlayPortalController();
  final LayerLink _link = LayerLink();
  final GlobalKey _fieldKey = GlobalKey();
  double _fieldWidth = 0;
  double _offsetDx = 0;

  String get _current {
    for (final option in widget.options) {
      if (option.value == widget.value) return option.label;
    }
    return '${widget.value}';
  }

  void _toggle() {
    if (!widget.enabled) return;
    // AlertDialog 会用 IntrinsicWidth 量内容，LayoutBuilder 在里面会抛「不支持内在尺寸」。
    // 所以宽度改成展开的那一刻从渲染对象上读。
    final box = _fieldKey.currentContext?.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      // 紧凑形态的字段很窄（只有「gvisor」几个字），浮层照抄宽度会把文字折行。
      _fieldWidth = widget.compact
          ? (box.size.width < 176 ? 176.0 : box.size.width)
          : box.size.width;
      // 靠右的下拉（设置页那种）浮层会顶出屏幕，这里往左挪回可视范围。
      final origin = box.localToGlobal(Offset.zero);
      final screenWidth = MediaQuery.sizeOf(context).width;
      final overflow = origin.dx + _fieldWidth + 8 - screenWidth;
      _offsetDx = overflow > 0 ? -overflow : 0;
    }
    if (_portal.isShowing) {
      _portal.hide();
    } else {
      _portal.show();
    }
    setState(() {});
  }

  void _close() {
    if (!_portal.isShowing) return;
    _portal.hide();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    final field = KeyedSubtree(
      key: _fieldKey,
      child: CompositedTransformTarget(
        link: _link,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: _toggle,
          child: widget.compact
              ? _compactField(context, scheme)
              : _formField(context, scheme),
        ),
      ),
    );

    return OverlayPortal(
      controller: _portal,
      overlayChildBuilder: (context) => Stack(
        children: [
          // 点空白处收起。
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: _close,
            ),
          ),
          CompositedTransformFollower(
            link: _link,
            showWhenUnlinked: false,
            targetAnchor: Alignment.bottomLeft,
            followerAnchor: Alignment.topLeft,
            offset: Offset(_offsetDx, 6),
            child: Align(
              alignment: Alignment.topLeft,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: const Duration(milliseconds: 130),
                curve: Curves.easeOutCubic,
                builder: (context, t, child) => Opacity(
                  opacity: t,
                  child: Transform.scale(
                    scale: 0.97 + 0.03 * t,
                    alignment: Alignment.topCenter,
                    child: child,
                  ),
                ),
                child: _menu(context, scheme),
              ),
            ),
          ),
        ],
      ),
      child: widget.compact || !widget.expand
          ? field
          : SizedBox(width: double.infinity, child: field),
    );
  }

  Widget _compactField(BuildContext context, ColorScheme scheme) {
    final enabled = widget.enabled;
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: Insets.xs + 2,
        vertical: Insets.xs,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            _current,
            style: mono(
              12,
              color: enabled ? scheme.primary : scheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(width: 2),
          Icon(
            Icons.expand_more,
            size: 17,
            color: enabled ? scheme.primary : scheme.onSurfaceVariant,
          ),
        ],
      ),
    );
  }

  Widget _formField(BuildContext context, ColorScheme scheme) {
    final enabled = widget.enabled;
    return InputDecorator(
      decoration: InputDecoration(
        labelText: widget.label,
        helperText: widget.helper,
        prefixIcon: widget.icon == null ? null : Icon(widget.icon, size: 19),
        // 输入框本身不接收文本，焦点交给外层的手势。
        enabled: enabled,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: 14,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              _current,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: display(14, weight: 500),
            ),
          ),
          Icon(
            Icons.expand_more,
            size: 19,
            color: enabled ? scheme.onSurfaceVariant : scheme.outline,
          ),
        ],
      ),
    );
  }

  Widget _menu(BuildContext context, ColorScheme scheme) {
    final width = _fieldWidth <= 0 ? 200.0 : _fieldWidth;
    return SizedBox(
      width: width,
      child: Container(
        constraints: const BoxConstraints(maxHeight: 320),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(Radius.circular(14)),
          border: Border.all(color: scheme.outlineVariant),
          boxShadow: const [
            BoxShadow(
              color: Color(0x33000000),
              blurRadius: 24,
              offset: Offset(0, 10),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final option in widget.options)
                _menuItem(context, scheme, option),
            ],
          ),
        ),
      ),
    );
  }

  Widget _menuItem(
    BuildContext context,
    ColorScheme scheme,
    DropdownOption<T> option,
  ) {
    final selected = option.value == widget.value;
    return InkWell(
      onTap: () {
        _portal.hide();
        setState(() {});
        if (!selected) widget.onChanged(option.value);
      },
      child: Container(
        width: double.infinity,
        color: selected ? scheme.primary.withValues(alpha: 0.16) : null,
        padding: const EdgeInsets.symmetric(
          horizontal: Insets.md,
          vertical: Insets.sm + 2,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    option.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    softWrap: false,
                    style: display(
                      14,
                      weight: selected ? 600 : 500,
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                  if (option.subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(option.subtitle!, style: hintStyle(context)),
                  ],
                ],
              ),
            ),
            if (selected) Icon(Icons.check, size: 17, color: scheme.primary),
          ],
        ),
      ),
    );
  }
}
