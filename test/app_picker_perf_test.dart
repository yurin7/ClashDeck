import 'dart:typed_data';

import 'package:clashdeck/runtime/platform_apps.dart';
import 'package:clashdeck/ui/app_picker_page.dart';
import 'package:clashdeck/ui/widgets/selectable_tile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 300+ 应用的加载/滚动性能：只打印耗时 + 做确定性断言，不设 CI 阈值
/// （与规则列表性能测试同一策略：机器差异太大，阈值会变成噪声）。
void main() {
  testWidgets('320 个应用：骨架首帧、列表帧与连续滚动耗时', (tester) async {
    final apps = <AppEntry>[
      for (var i = 0; i < 320; i++)
        AppEntry(
          package: 'com.example.app$i',
          label: '应用 ${i.toString().padLeft(3, '0')}',
        ),
    ];

    final watch = Stopwatch();
    watch.start();
    await tester.pumpWidget(
      MaterialApp(
        home: AppPickerPage(
          selected: const [],
          title: '选择应用',
          appLoader: () async => apps,
          iconLoader: (_) async => const <String, Uint8List>{},
          minimumLoad: Duration.zero,
          iconBatchSize: 32,
        ),
      ),
    );
    watch.stop();
    debugPrint('[perf] 骨架首帧 ${watch.elapsedMicroseconds / 1000}ms');
    expect(find.byKey(const Key('app-picker-skeleton')), findsOneWidget);

    watch
      ..reset()
      ..start();
    await tester.pump(const Duration(milliseconds: 1));
    await tester.pump();
    watch.stop();
    debugPrint('[perf] 列表首帧 ${watch.elapsedMicroseconds / 1000}ms');
    expect(find.text('应用 000'), findsOneWidget);

    // 懒构建：可见行远少于 320。
    final built = tester.widgetList(find.byType(SelectableTile)).length;
    debugPrint('[perf] 首屏构建行数 $built');
    expect(built, lessThan(40));

    watch
      ..reset()
      ..start();
    for (var i = 0; i < 10; i++) {
      await tester.drag(find.byType(ListView), const Offset(0, -480));
      await tester.pump();
    }
    watch.stop();
    debugPrint('[perf] 连续滚动 10 次 ${watch.elapsedMicroseconds / 1000}ms');
    expect(find.byType(ListView), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
