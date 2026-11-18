import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/motion.dart';

Widget _host(Widget child, {bool disableAnimations = false}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: disableAnimations),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  Future<Motion> motionOf(
    WidgetTester tester, {
    bool disableAnimations = false,
  }) async {
    late Motion motion;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) {
            motion = Motion.of(context);
            return const SizedBox();
          },
        ),
        disableAnimations: disableAnimations,
      ),
    );
    return motion;
  }

  testWidgets('默认时长与曲线走 normal token', (tester) async {
    final motion = await motionOf(tester);
    expect(motion.fast, const Duration(milliseconds: 140));
    expect(motion.chip, const Duration(milliseconds: 140));
    expect(motion.arrow, const Duration(milliseconds: 180));
    expect(motion.expand, const Duration(milliseconds: 220));
    expect(motion.page, const Duration(milliseconds: 300));
    expect(motion.enter, Curves.easeOutCubic);
    expect(motion.exit, Curves.easeInCubic);
  });

  testWidgets('减少动画时全部降为 60ms', (tester) async {
    final motion = await motionOf(tester, disableAnimations: true);
    expect(motion.fast, const Duration(milliseconds: 60));
    expect(motion.chip, const Duration(milliseconds: 60));
    expect(motion.arrow, const Duration(milliseconds: 60));
    expect(motion.expand, const Duration(milliseconds: 60));
    expect(motion.page, const Duration(milliseconds: 60));
  });

  testWidgets('MotionEntrance 结束后完全显示且为 1 倍', (tester) async {
    await tester.pumpWidget(_host(const MotionEntrance(child: Text('内容'))));
    expect(find.text('内容'), findsOneWidget);
    await tester.pumpAndSettle();
    final transform = tester.widget<Transform>(find.byType(Transform).first);
    expect(transform.transform.getMaxScaleOnAxis(), closeTo(1, 0.001));
  });

  testWidgets('MotionEntrance 在减少动画下仍能落到终态', (tester) async {
    await tester.pumpWidget(
      _host(const MotionEntrance(child: Text('内容')), disableAnimations: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('内容'), findsOneWidget);
  });
}
