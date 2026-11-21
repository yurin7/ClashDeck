import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/motion.dart';
import 'package:clashdeck/ui/runtime_page.dart';
import 'package:clashdeck/ui/widgets/start_stop_button.dart';

class _TestRuntime extends RuntimeController {
  _TestRuntime(EditorState state) : super(configProvider: () => state.doc);

  void reportPhase(RuntimePhase phase) {
    debugSetPhase(phase);
    notifyListeners();
  }
}

void main() {
  testWidgets('启动 / 停止 / 处理中三种状态按钮同宽同高', (tester) async {
    var phase = RuntimePhase.idle;
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
                    phase: phase,
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

    setState(() => phase = RuntimePhase.running);
    await tester.pumpAndSettle();
    final stop = tester.getSize(find.byKey(const ValueKey('start-stop-stop')));
    expect(stop.width, start.width);
    expect(stop.height, start.height);

    setState(() => phase = RuntimePhase.stopping);
    await tester.pumpAndSettle();
    final busyStop = tester.getSize(
      find.byKey(const ValueKey(RuntimePhase.stopping)),
    );
    expect(busyStop.width, start.width);
    expect(busyStop.height, start.height);
    expect(find.text('停止中…'), findsOneWidget);
  });

  testWidgets('运行页启停保留按钮淡出，图表连续推移按钮位置', (tester) async {
    final state = EditorState(doc: YamlDoc.parse('rules: [MATCH,DIRECT]'));
    final runtime = _TestRuntime(state);
    addTearDown(state.dispose);
    addTearDown(runtime.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: RuntimePage(state: state, controller: runtime),
      ),
    );
    final control = find.byType(StartStopButton);
    double buttonTop() => tester.getTopLeft(control).dy;
    final idleTop = buttonTop();

    runtime.reportPhase(RuntimePhase.starting);
    await tester.pump();
    expect(find.text('启动内核'), findsOneWidget);
    expect(find.text('启动中…'), findsOneWidget);
    await tester.pumpAndSettle();

    runtime.reportPhase(RuntimePhase.running);
    runtime.reportPhase(RuntimePhase.running);
    await tester.pump();
    expect(find.text('启动中…'), findsOneWidget);
    expect(find.text('停止内核'), findsOneWidget);
    expect(buttonTop(), idleTop);
    await tester.pump(Motion.normal.expand ~/ 2);
    final expandingTop = buttonTop();
    await tester.pump(Motion.normal.expand);
    final runningTop = buttonTop();
    expect(expandingTop, inExclusiveRange(idleTop, runningTop));

    runtime.reportPhase(RuntimePhase.stopping);
    await tester.pump();
    expect(find.text('停止内核'), findsOneWidget);
    expect(find.text('停止中…'), findsOneWidget);
    expect(buttonTop(), runningTop);
    await tester.pump(Motion.normal.expand ~/ 2);
    expect(buttonTop(), inExclusiveRange(idleTop, runningTop));

    runtime.reportPhase(RuntimePhase.idle);
    await tester.pumpAndSettle();
    expect(buttonTop(), idleTop);
    expect(find.text('启动内核'), findsOneWidget);
    expect(find.text('停止内核'), findsNothing);
  });
}
