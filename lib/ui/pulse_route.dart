import 'package:material_ui/material_ui.dart';

import 'motion.dart';

/// Pulse 用的「叠加层」路由：不透明页会盖住主界面，这里要求下层保持可见
/// （被 barrier 压暗），形成一层浮起来的负一屏，而不是又一个页面。
Route<T> pulseRoute<T>(WidgetBuilder builder) {
  return PageRouteBuilder<T>(
    opaque: true,
    barrierColor: const Color(0x99000000),
    barrierDismissible: true,
    barrierLabel: '关闭 Pulse',
    transitionDuration: kPulseEnterDuration,
    reverseTransitionDuration: kPulseExitDuration,
    pageBuilder: (context, animation, secondaryAnimation) => builder(context),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.08, 0),
            end: Offset.zero,
          ).animate(curved),
          child: ScaleTransition(
            scale: Tween<double>(begin: 0.985, end: 1).animate(curved),
            child: child,
          ),
        ),
      );
    },
  );
}
