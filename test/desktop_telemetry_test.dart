import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:clashdeck/runtime/windows_connections.dart';
import 'package:clashdeck/runtime/windows_kernel.dart';
import 'package:clashdeck/ui/desktop_activity.dart';
import 'package:clashdeck/ui/desktop_connections.dart';
import 'package:clashdeck/ui/desktop_traffic.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('点击曲线保留读数，恢复实时后跟随最新采样', (tester) async {
    final time = DateTime(2026, 11, 22, 10, 59);
    final readings = <RuntimeTrafficSample>[
      (at: time.subtract(const Duration(seconds: 1)), up: 512, down: 2048),
      (at: time, up: 1024, down: 4096),
    ];
    Future<void> showChart({bool reduceMotion = false}) => tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 660,
              child: DesktopTrafficChart(
                samples: List.of(readings),
                running: true,
              ),
            ),
          ),
        ),
      ),
    );

    await showChart();
    final plot = tester.getRect(
      find.byKey(const ValueKey('desktop-traffic-plot')),
    );
    await tester.tapAt(Offset(plot.right - 3, plot.center.dy));
    await tester.pumpAndSettle();
    expect(find.text('已暂停'), findsOneWidget);
    readings.add((
      at: time.add(const Duration(seconds: 1)),
      up: 2048,
      down: 8192,
    ));
    await showChart();
    expect(find.text('4.0'), findsOneWidget);
    expect(find.text('8.0'), findsNothing);
    await tester.tap(find.byTooltip('恢复实时'));
    await tester.pumpAndSettle();
    expect(find.text('8.0'), findsOneWidget);
    expect(find.text('已暂停'), findsNothing);

    readings.add((
      at: time.add(const Duration(seconds: 2)),
      up: 2048,
      down: 16384,
    ));
    await showChart();
    expect(find.text('8.0'), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text('16.0'), findsOneWidget);

    readings.add((
      at: time.add(const Duration(seconds: 3)),
      up: 2048,
      down: 32768,
    ));
    await showChart(reduceMotion: true);
    expect(find.text('32.0'), findsOneWidget);
  });

  testWidgets('点击流量排行中的进程，连接页随即筛到该进程', (tester) async {
    final kernel = RuntimeController(
      configProvider: () => YamlDoc.parse('proxies: []'),
      windowsKernel: WindowsKernel(),
    );
    final monitor = WindowsConnectionMonitor(kernel, () => const {});
    final search = FocusNode();
    addTearDown(() {
      monitor.dispose();
      kernel.dispose();
      search.dispose();
    });
    Map<String, Object?> snapshot(int bytes) => {
      'downloadTotal': bytes,
      'connections': [
        {
          'id': 'node',
          'download': bytes,
          'metadata': {
            'host': 'audio.example.test',
            'destinationPort': '443',
            'process': 'node.exe',
          },
        },
        {
          'id': 'web',
          'download': bytes ~/ 2,
          'metadata': {
            'host': 'static.example.test',
            'destinationPort': '443',
            'process': 'browser.exe',
          },
        },
      ],
    };
    monitor.history.apply(
      snapshot(1024),
      at: Duration.zero,
      groupNames: const {},
    );
    monitor.history.apply(
      snapshot(4096),
      at: const Duration(seconds: 1),
      groupNames: const {},
    );
    String? inspected;
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) => IndexedStack(
              index: inspected == null ? 0 : 1,
              children: [
                DesktopActivity(
                  monitor: monitor,
                  visible: inspected == null,
                  onOpenConnections: () {},
                  onInspectProcess: (process) =>
                      setState(() => inspected = process),
                ),
                DesktopConnections(
                  monitor: monitor,
                  visible: inspected != null,
                  searchFocus: search,
                  inspectProcess: inspected,
                  onOpenOverview: () {},
                ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('node.exe'));
    await tester.pumpAndSettle();
    expect(find.text('audio.example.test:443'), findsOneWidget);
    expect(find.text('static.example.test:443'), findsNothing);
    expect(find.byTooltip('恢复默认顺序'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
