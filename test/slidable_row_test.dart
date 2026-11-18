import 'package:clashdeck/ui/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

Widget _host(Widget row) => MaterialApp(
  home: Scaffold(body: Center(child: row)),
);

void main() {
  testWidgets('整行按传入圆角裁剪（内容与红块共用）', (tester) async {
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
    expect(find.byType(ClipRect), findsNothing);
  });

  testWidgets('点删除先收起行，再执行删除动作', (tester) async {
    final events = <String>[];
    var open = true;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          SlidableRow(
            actionLabel: '删除',
            borderRadius: const BorderRadius.all(Radius.circular(16)),
            open: open,
            onOpenChanged: (value) {
              events.add('open:$value');
              setState(() => open = value);
            },
            onAction: () => events.add('action'),
            child: const SizedBox(height: 56, child: Text('行')),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();

    // 顺序必须是「先收起再删」，否则确认框会盖在半开的行上。
    expect(events, ['open:false', 'action']);
    expect(open, isFalse);
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
}
