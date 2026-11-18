import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/widgets/start_stop_button.dart';

void main() {
  testWidgets('启动 / 停止 / 处理中三种状态按钮同宽同高', (tester) async {
    var running = false;
    var busy = false;
    late StateSetter setState;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 320,
              child: StatefulBuilder(
                builder: (context, innerSetState) {
                  setState = innerSetState;
                  return StartStopButton(
                    running: running,
                    busy: busy,
                    onStart: () {},
                    onStop: () {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    final start = tester.getSize(
      find.byKey(const ValueKey('start-stop-start')),
    );
    expect(start.width, 320);
    expect(start.height, 46);

    setState(() => running = true);
    await tester.pumpAndSettle();
    final stop = tester.getSize(find.byKey(const ValueKey('start-stop-stop')));
    expect(stop.width, start.width);
    expect(stop.height, start.height);

    setState(() => busy = true);
    await tester.pumpAndSettle();
    final busyStop = tester.getSize(
      find.byKey(const ValueKey('start-stop-busy')),
    );
    expect(busyStop.width, start.width);
    expect(busyStop.height, start.height);
  });
}
