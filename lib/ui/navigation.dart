import 'package:material_ui/material_ui.dart';

/// 全站页面跳转：右进左出 + 轻微淡入。
///
/// 不用 [MaterialPageRoute] 的默认 zoom/fade（安卓上会显得突兀），
/// 进入 300ms easeOutCubic，返回 260ms easeInCubic。
Route<T> appRoute<T>(Widget page) {
  return PageRouteBuilder<T>(
    pageBuilder: (context, animation, secondaryAnimation) => page,
    transitionDuration: const Duration(milliseconds: 300),
    reverseTransitionDuration: const Duration(milliseconds: 260),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      final offset = Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(curved);
      final fade = Tween<double>(begin: 0.6, end: 1).animate(curved);
      return SlideTransition(
        position: offset,
        child: FadeTransition(opacity: fade, child: child),
      );
    },
  );
}
