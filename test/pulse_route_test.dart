import 'package:clashdeck/ui/pulse_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pulseRoute 是透明叠加层，点页面外边距关闭', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => Navigator.of(context).push(
                pulseRoute<void>(
                  (_) => GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => Navigator.of(context).maybePop(),
                    child: const Scaffold(
                      backgroundColor: Colors.transparent,
                      body: Center(child: Text('pulse')),
                    ),
                  ),
                ),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('pulse'), findsOneWidget);

    final route = ModalRoute.of(tester.element(find.text('pulse')))!;
    expect(route.opaque, isFalse);
    expect(route.barrierDismissible, isTrue);
    expect(route.barrierColor, const Color(0x99000000));
    expect(find.byType(ModalBarrier), findsWidgets);

    // 点遮罩（页面中央以外）收起叠加层，下层主界面仍在。
    await tester.tapAt(const Offset(6, 6));
    await tester.pumpAndSettle();
    expect(find.text('pulse'), findsNothing);
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('pulseRoute 的转场是淡入 + 位移 + 缩放', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () => Navigator.of(context).push(
              pulseRoute<void>(
                (_) => const Scaffold(
                  backgroundColor: Colors.transparent,
                  body: Text('pulse'),
                ),
              ),
            ),
            child: const Text('open'),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    expect(find.byType(FadeTransition), findsWidgets);
    expect(find.byType(SlideTransition), findsWidgets);
    expect(find.byType(ScaleTransition), findsWidgets);
    await tester.pumpAndSettle();
  });
}
