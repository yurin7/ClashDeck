import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:clashdeck/ui/pulse_entry.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:clashdeck/ui/widgets/pulse_edge_handle.dart';

void main() {
  testWidgets('右缘把手是 24dp 宽的竖条 + 左箭头', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: const Scaffold(body: Stack(children: [PulseEdgeHandle()])),
      ),
    );
    await tester.pump();

    final handle = find.byType(PulseEdgeHandle);
    expect(handle, findsOneWidget);
    expect(find.byIcon(Icons.chevron_left_rounded), findsOneWidget);

    final bar = find.descendant(of: handle, matching: find.byType(Container));
    expect(bar, findsOneWidget);
    final size = tester.getSize(bar);
    expect(size.width, kPulseEdgeHandleWidth);
    expect(size.height, 72);
  });
}
