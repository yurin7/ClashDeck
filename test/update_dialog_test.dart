import 'package:clashdeck/core/update/update_check.dart';
import 'package:clashdeck/ui/update_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

UpdateInfo _info() => UpdateInfo(
  version: '0.2.2',
  url: 'https://github.com/yurin7/ClashDeck/releases/tag/v0.2.2',
  notes: '- 修复 A\n- 修复 B\n- 新增 C',
  publishedAt: DateTime(2026, 11, 19),
);

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required Future<bool> Function(String) openUrl,
    void Function(bool?)? onResult,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  final result = await showUpdateDialog(
                    context,
                    _info(),
                    openUrl: openUrl,
                  );
                  onResult?.call(result);
                },
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
  }

  testWidgets('展示版本、日期与更新说明', (tester) async {
    await pumpHost(tester, openUrl: (_) async => true);
    expect(find.text('发现新版本'), findsOneWidget);
    expect(find.text('v0.2.2'), findsOneWidget);
    expect(find.text('2026-11-19'), findsOneWidget);
    expect(find.textContaining('修复 A'), findsOneWidget);
    expect(find.text('去下载'), findsOneWidget);
    expect(find.text('取消'), findsOneWidget);
  });

  testWidgets('点去下载 → 用 Release 地址打开并关闭', (tester) async {
    String? opened;
    bool? result;
    await pumpHost(
      tester,
      openUrl: (url) async {
        opened = url;
        return true;
      },
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('去下载'));
    await tester.pumpAndSettle();
    expect(opened, _info().url);
    expect(result, isTrue);
    expect(find.text('发现新版本'), findsNothing);
  });

  testWidgets('取消返回 false 且不打开浏览器', (tester) async {
    var opened = 0;
    bool? result;
    await pumpHost(
      tester,
      openUrl: (_) async {
        opened++;
        return true;
      },
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(opened, 0);
    expect(result, isFalse);
  });

  testWidgets('说明为空时给占位文案', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () => showUpdateDialog(
                  context,
                  UpdateInfo(version: '0.2.2', url: 'x', notes: ''),
                  openUrl: (_) async => true,
                ),
                child: const Text('打开'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('打开'));
    await tester.pumpAndSettle();
    expect(find.text('这次没有写更新说明。'), findsOneWidget);
  });
}
