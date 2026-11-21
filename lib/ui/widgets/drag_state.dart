import 'package:material_ui/material_ui.dart';

/// 一次拖拽结束时的回弹请求：把拖拽浮层从落点滑回源胶囊的位置。
class DragSnapBack {
  const DragSnapBack({
    required this.member,
    required this.fromGroup,
    required this.sourceRect,
    required this.endOffset,
    required this.feedbackSize,
    this.duplicateGroup,
  });

  final String member;
  final String? fromGroup;
  final Rect sourceRect;
  final Offset endOffset;
  final Size feedbackSize;

  /// 非空表示目标组已有该成员，回弹结束后要提示。
  final String? duplicateGroup;
}

/// 跨组件共享的拖拽状态：
///
/// - 成员胶囊在拖拽开始时登记源位置，结束时登记落点；
/// - 组卡的 `DragTarget` 在悬停到已有该成员的组时标记重复；
/// - `ProxyBoard` 用源位置与落点播放一次 240ms 的回弹动画。
class DragState extends ChangeNotifier {
  bool _dragging = false;
  bool _accepted = false;
  bool _animating = false;
  String? _memberName;
  String? _fromGroup;
  Rect? _sourceRect;
  Size? _feedbackSize;
  Offset? _endOffset;
  String? _duplicateGroup;

  bool get dragging => _dragging;

  /// 回弹动画期间禁止再次发起拖拽。
  bool get animating => _animating;

  bool get blocked => _duplicateGroup != null;

  String? get duplicateGroup => _duplicateGroup;

  String? get fromGroup => _fromGroup;

  Rect? get sourceRect => _sourceRect;

  Size? get feedbackSize => _feedbackSize;

  void begin({
    required String member,
    String? group,
    required Rect sourceRect,
    required Size feedbackSize,
  }) {
    _dragging = true;
    _accepted = false;
    _animating = false;
    _memberName = member;
    _fromGroup = group;
    _sourceRect = sourceRect;
    _feedbackSize = feedbackSize;
    _endOffset = null;
    _duplicateGroup = null;
    notifyListeners();
  }

  /// 悬停在已有该成员的组上；传 null 清除。
  void hintDuplicate(String? group) {
    if (_duplicateGroup == group) return;
    _duplicateGroup = group;
    notifyListeners();
  }

  void clearHint() => hintDuplicate(null);

  /// 落在合法目标上：不再回弹。
  void markAccepted() {
    _accepted = true;
  }

  /// 拖拽结束：返回这次是否需要回弹（被拒绝、落在空白或拖回原位）。
  bool end(Offset endOffset) {
    if (!_dragging) return false;
    final shouldSnapBack = !_accepted;
    _dragging = false;
    _accepted = false;
    if (shouldSnapBack) {
      _endOffset = endOffset;
    } else {
      // 已落到合法目标：不留回弹信息，避免随后被误播。
      _sourceRect = null;
      _feedbackSize = null;
      _endOffset = null;
      _memberName = null;
      _fromGroup = null;
      _duplicateGroup = null;
    }
    notifyListeners();
    return shouldSnapBack;
  }

  /// 取出待播放的回弹；没有或已在播放则返回 null。
  DragSnapBack? takeSnapBack() {
    final source = _sourceRect;
    final end = _endOffset;
    final size = _feedbackSize;
    final member = _memberName;
    if (source == null || end == null || size == null || member == null) {
      return null;
    }
    if (_animating) return null;
    _animating = true;
    return DragSnapBack(
      member: member,
      fromGroup: _fromGroup,
      sourceRect: source,
      endOffset: end,
      feedbackSize: size,
      duplicateGroup: _duplicateGroup,
    );
  }

  /// 回弹动画结束：清掉本次拖拽的临时信息并解除禁止拖拽。
  void finishSnapBack() {
    _animating = false;
    _sourceRect = null;
    _feedbackSize = null;
    _endOffset = null;
    _memberName = null;
    _fromGroup = null;
    _duplicateGroup = null;
    notifyListeners();
  }

  void reset() {
    _dragging = false;
    _accepted = false;
    _animating = false;
    _memberName = null;
    _fromGroup = null;
    _sourceRect = null;
    _feedbackSize = null;
    _endOffset = null;
    _duplicateGroup = null;
    notifyListeners();
  }
}

/// 全局单例：拖拽浮层在 Overlay、目标在组卡、回弹在 ProxyBoard，需要共享同一份状态。
final DragState dragState = DragState();
