import 'package:clashdeck/ui/pulse_drawer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> setSize(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.binding.setSurfaceSize(size);
    addTearDown(() => tester.binding.setSurfaceSize(null));
  }

  testWidgets('面板宽度是屏宽的 80%', (tester) async {
    await setSize(tester, const Size(400, 800));
    const panelKey = Key('panel');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseDrawer(
            progress: 1,
            onClose: () {},
            child: const SizedBox.expand(key: panelKey),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(tester.getSize(find.byKey(panelKey)).width, 320);
  });

  testWidgets('点左侧暗区会请求收起', (tester) async {
    await setSize(tester, const Size(400, 800));
    var closed = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseDrawer(
            progress: 1,
            onClose: () => closed++,
            child: const SizedBox.expand(),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tapAt(const Offset(40, 400));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('收起时面板退回屏外，暗区消失', (tester) async {
    await setSize(tester, const Size(400, 800));
    const panelKey = Key('panel');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PulseDrawer(
            progress: 0,
            onClose: () {},
            child: const SizedBox.expand(key: panelKey),
          ),
        ),
      ),
    );
    await tester.pump();
    final rect = tester.getRect(find.byKey(panelKey));
    expect(rect.left, 400);
  });

  testWidgets('开合抽屉不会丢掉概览的滚动位置', (tester) async {
    await setSize(tester, const Size(400, 800));
    final inner = ScrollController();
    addTearDown(inner.dispose);
    await tester.pumpWidget(_Harness(inner: inner));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -220));
    await tester.pumpAndSettle();
    final before = inner.offset;
    expect(before, greaterThan(0));

    await tester.tap(find.byKey(const ValueKey('open')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer')), findsOneWidget);

    await tester.tapAt(const Offset(20, 400));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('drawer')), findsNothing);
    expect(inner.offset, before);
  });
}

class _Harness extends StatefulWidget {
  const _Harness({required this.inner});

  final ScrollController inner;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Stack(
          children: [
            ListView.builder(
              controller: widget.inner,
              itemCount: 40,
              itemBuilder: (context, i) =>
                  SizedBox(height: 60, child: Text('row $i')),
            ),
            Positioned(
              left: 8,
              top: 8,
              child: TextButton(
                key: const ValueKey('open'),
                onPressed: () => setState(() => _open = true),
                child: const Text('open'),
              ),
            ),
            if (_open)
              Positioned.fill(
                child: KeyedSubtree(
                  key: const ValueKey('drawer'),
                  child: PulseDrawer(
                    progress: 1,
                    onClose: () => setState(() => _open = false),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
