import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget row) => MaterialApp(
  home: Scaffold(body: Center(child: row)),
);

void main() {
  testWidgets('传了 borderRadius 就用同圆角裁整行，不传仍用矩形裁剪', (tester) async {
    const radius = BorderRadius.all(Radius.circular(16));
    await tester.pumpWidget(
      _host(
        SlidableRow(
          actionLabel: '删除',
          onAction: () {},
          borderRadius: radius,
          child: const SizedBox(height: 56, child: Text('行')),
        ),
      ),
    );
    expect(
      tester.widget<ClipRRect>(find.byType(ClipRRect)).borderRadius,
      radius,
    );

    await tester.pumpWidget(
      _host(
        SlidableRow(
          actionLabel: '删除',
          onAction: () {},
          child: const SizedBox(height: 56, child: Text('行')),
        ),
      ),
    );
    expect(find.byType(ClipRect), findsOneWidget);
    expect(find.byType(ClipRRect), findsNothing);
  });

  testWidgets('展开时红块在行 rect 内，内容尺寸不变', (tester) async {
    const radius = BorderRadius.all(Radius.circular(16));
    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SlidableRow(
            actionLabel: '删除',
            onAction: () {},
            borderRadius: radius,
            child: const SizedBox(
              key: ValueKey('row'),
              height: 56,
              child: Text('行'),
            ),
          ),
        ),
      ),
    );

    final before = tester.getSize(find.byKey(const ValueKey('row')));
    final rowRect = tester.getRect(find.byType(SlidableRow));

    await tester.pumpWidget(
      _host(
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: SlidableRow(
            actionLabel: '删除',
            onAction: () {},
            borderRadius: radius,
            open: true,
            child: const SizedBox(
              key: ValueKey('row'),
              height: 56,
              child: Text('行'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 内容尺寸不变，只是被整体左移让出 80dp。
    expect(tester.getSize(find.byKey(const ValueKey('row'))), before);
    final contentRect = tester.getRect(find.byKey(const ValueKey('row')));
    expect(contentRect.right, lessThanOrEqualTo(rowRect.right));

    // 删除按钮落在行 rect 内侧。
    final actionRect = tester.getRect(find.text('删除'));
    expect(actionRect.right, lessThanOrEqualTo(rowRect.right + 0.5));
    expect(actionRect.left, greaterThanOrEqualTo(rowRect.right - 80 - 0.5));
    expect(actionRect.top, greaterThanOrEqualTo(rowRect.top - 0.5));
    expect(actionRect.bottom, lessThanOrEqualTo(rowRect.bottom + 0.5));
  });

  testWidgets('点删除触发 onAction', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        SlidableRow(
          actionLabel: '删除',
          onAction: () => taps++,
          borderRadius: const BorderRadius.all(Radius.circular(16)),
          open: true,
          child: const SizedBox(height: 56, child: Text('行')),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(taps, 1);
  });
}
