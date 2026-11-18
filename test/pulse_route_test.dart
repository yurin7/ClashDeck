import 'package:clashdeck/ui/pulse_route.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('pulseRoute 铺满整屏，下层 UI 不可见，返回可关闭', (tester) async {
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
    expect(route.opaque, isTrue);
    expect(route.barrierColor, const Color(0x99000000));
    expect(find.byType(ModalBarrier), findsWidgets);

    // 页面占满整屏，因此不靠点遮罩关闭；用返回 / 右滑 / 下滑收起。
    Navigator.of(tester.element(find.text('pulse'))).pop();
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
