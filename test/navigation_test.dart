import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/navigation.dart';

void main() {
  test('appRoute：进入 300ms、返回 260ms，且是 PageRouteBuilder', () {
    final route = appRoute<void>(const SizedBox()) as PageRouteBuilder<void>;
    expect(route.transitionDuration, const Duration(milliseconds: 300));
    expect(route.reverseTransitionDuration, const Duration(milliseconds: 260));
  });

  testWidgets('appRoute：右滑入 + 淡入，返回时反向', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () =>
                  Navigator.of(context).push(appRoute<void>(const _Second())),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 150));

    // 转场中：两个页面同时在树上，新页面从右侧滑入、透明度尚未到 1。
    expect(find.text('第二页'), findsOneWidget);
    final slide = tester.widget<SlideTransition>(
      find
          .ancestor(
            of: find.text('第二页'),
            matching: find.byType(SlideTransition),
          )
          .first,
    );
    final dx = slide.position.value.dx;
    expect(dx, greaterThan(0));
    expect(dx, lessThan(1));

    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(of: find.text('第二页'), matching: find.byType(FadeTransition))
          .first,
    );
    expect(fade.opacity.value, greaterThan(0.6));
    expect(fade.opacity.value, lessThan(1));

    // 300ms 后落定。
    await tester.pumpAndSettle();
    expect(find.text('第二页'), findsOneWidget);
    expect(find.text('打开'), findsNothing);

    // 返回：先回退，再落回首页。
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    navigator.pop();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 130));
    expect(find.text('打开'), findsOneWidget);
    expect(find.text('第二页'), findsOneWidget);

    await tester.pumpAndSettle();
    expect(find.text('打开'), findsOneWidget);
    expect(find.text('第二页'), findsNothing);
  });
}

class _Second extends StatelessWidget {
  const _Second();

  @override
  Widget build(BuildContext context) => const Scaffold(body: Text('第二页'));
}
