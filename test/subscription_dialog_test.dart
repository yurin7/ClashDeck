import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/core/parse/subscription.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/ui/import_dialogs.dart';

Future<void> _open(
  WidgetTester tester, {
  String initial = '',
  Future<SubscriptionResult> Function(String url)? fetch,
  required void Function(SubscriptionInput?) onResult,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () async {
              final result = await showSubscriptionDialog(
                ctx,
                initialUrl: initial,
                fetch: fetch,
              );
              onResult(result);
            },
            child: const Text('打开'),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('地址为空时点保存：就地报错，不关窗', (tester) async {
    await _open(tester, initial: '', onResult: (_) {});
    expect(find.text('订阅链接'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('先填订阅地址'), findsOneWidget);
    expect(find.text('订阅链接'), findsOneWidget);
    expect(find.text('是否立即同步此订阅？'), findsNothing);
  });

  testWidgets('非 http(s) 地址不进入同步确认', (tester) async {
    await _open(tester, initial: 'ftp://example.com/sub', onResult: (_) {});
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pump();

    expect(find.text('地址需要以 http:// 或 https:// 开头'), findsOneWidget);
    expect(find.text('是否立即同步此订阅？'), findsNothing);
  });

  testWidgets('选「稍后」只保存地址，不联网', (tester) async {
    var calls = 0;
    SubscriptionInput? out;
    await _open(
      tester,
      initial: 'https://example.com/sub',
      fetch: (url) async {
        calls++;
        return const SubscriptionResult(
          proxies: <Map<String, Object?>>[
            <String, Object?>{'name': 'n1'},
          ],
          title: 'T',
        );
      },
      onResult: (r) => out = r,
    );

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('是否立即同步此订阅？'), findsOneWidget);

    await tester.tap(find.text('稍后'));
    await tester.pumpAndSettle();

    expect(calls, 0);
    expect(out, isNotNull);
    expect(out!.url, 'https://example.com/sub');
    expect(out!.result, isNull);
  });

  testWidgets('选「同步」才拉取，并把结果带回', (tester) async {
    final calls = <String>[];
    SubscriptionInput? out;
    await _open(
      tester,
      initial: 'https://example.com/sub',
      fetch: (url) async {
        calls.add(url);
        return const SubscriptionResult(
          proxies: <Map<String, Object?>>[
            <String, Object?>{'name': 'n1'},
          ],
          title: 'T',
        );
      },
      onResult: (r) => out = r,
    );

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步'));
    await tester.pumpAndSettle();

    expect(calls, <String>['https://example.com/sub']);
    expect(out, isNotNull);
    expect(out!.result, isNotNull);
    expect(out!.result!.count, 1);
  });

  testWidgets('同步失败时就地显示错误，窗口保留可重试', (tester) async {
    SubscriptionInput? out;
    await _open(
      tester,
      initial: 'https://example.com/sub',
      fetch: (url) async => throw ConfigEditException('boom'),
      onResult: (r) => out = r,
    );

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('同步'));
    await tester.pumpAndSettle();

    expect(find.text('boom'), findsOneWidget);
    expect(find.text('订阅链接'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();
    expect(out, isNull);
  });
}
