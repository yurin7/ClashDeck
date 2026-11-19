import 'dart:async';
import 'dart:io';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
proxies:
  - {name: A, type: ss, server: 127.0.0.1, port: 1, cipher: aes-128-gcm, password: pw}
  - {name: B, type: ss, server: 127.0.0.1, port: 2, cipher: aes-128-gcm, password: pw}
proxy-groups:
  - name: PROXY
    type: select
    proxies: [A, B]
rules:
  - MATCH,PROXY
''';

class _FakeSocket extends Fake implements Socket {
  @override
  void destroy() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channelName = 'test/proxy-board-delay';
  late Directory dir;
  RuntimeController? controller;

  Future<void> feedState(String state) async {
    final data = const StandardMethodCodec().encodeMethodCall(
      MethodCall('onRuntimeState', {'state': state, 'pid': 7}),
    );
    await TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .handlePlatformMessage(channelName, data, (_) {});
  }

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('clashdeck_delay_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), (
          call,
        ) async {
          return null;
        });
  });

  tearDown(() async {
    controller?.dispose();
    controller = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(channelName), null);
    await dir.delete(recursive: true);
  });

  RuntimeController make(Future<int?> Function(String) probe) =>
      RuntimeController(
        configProvider: () => YamlDoc.parse(_yaml),
        channel: const MethodChannel(channelName),
        androidOverride: true,
        workDirProvider: () async => dir.path,
        delayProbe: probe,
      );

  Future<void> pumpBoard(WidgetTester tester, RuntimeController runtime) async {
    final state = EditorState.fromText(_yaml, fileName: 'demo.yaml');
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ProxyBoard(state: state, runtime: runtime),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('手动测速完成 toast 带节点数量', (tester) async {
    controller = make((_) async => 42);
    await pumpBoard(tester, controller!);
    await feedState('running');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('测速全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('测速完成：2 个节点'), findsOneWidget);

    await feedState('stopped');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('测速中禁用入口并显示 done/total 进度', (tester) async {
    final gate = Completer<int?>();
    controller = make((_) => gate.future);
    await pumpBoard(tester, controller!);
    await feedState('running');
    await tester.pump();

    await tester.tap(find.byTooltip('测速全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    // 入口禁用（tooltip 变成进度文案），副标题显示 0/2。
    expect(find.byTooltip('测速中 0/2'), findsOneWidget);
    expect(find.text('测速中 0/2'), findsOneWidget);
    final icon = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.speed).first,
    );
    expect(icon.onPressed, isNull);

    gate.complete(23);
    await tester.pump();
    await feedState('stopped');
    await tester.pump(const Duration(seconds: 3));
  });

  testWidgets('内核未运行时入口可用，结果带 ≈ 标记', (tester) async {
    controller = RuntimeController(
      configProvider: () => YamlDoc.parse(_yaml),
      channel: const MethodChannel(channelName),
      androidOverride: true,
      workDirProvider: () async => dir.path,
      tcpConnector: (host, port, {timeout}) async => _FakeSocket(),
    );
    await pumpBoard(tester, controller!);

    final icon = tester.widget<IconButton>(
      find.widgetWithIcon(IconButton, Icons.speed).first,
    );
    expect(icon.onPressed, isNotNull);

    await tester.tap(find.byTooltip('测速全部'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('测速完成：2 个节点（≈ 为 TCP 近似值）'), findsOneWidget);
    expect(find.textContaining('≈'), findsWidgets);
    expect(controller!.approxDelays, containsAll(<String>['A', 'B']));
  });
}
