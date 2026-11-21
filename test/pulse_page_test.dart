import 'dart:async';
import 'dart:io';

import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/update/update_check.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/data/app_prefs.dart';
import 'package:clashdeck/runtime/speed_test.dart';
import 'package:clashdeck/ui/fields.dart';
import 'package:clashdeck/ui/pulse_page.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _yaml = '''
mixed-port: 7890
proxies:
  - name: HK-01
    type: ss
    server: 1.1.1.1
    port: 8388
    cipher: aes-128-gcm
    password: pw
  - name: JP-01
    type: ss
    server: 1.1.1.2
    port: 8388
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - HK-01
      - JP-01
rules:
  - MATCH,PROXY
''';

UpdateInfo _info() => UpdateInfo(
  version: '0.3.0',
  url: 'https://github.com/yurin7/ClashDeck/releases/tag/v0.3.0',
  notes: '- 新增 Pulse\n- 修复 A',
  publishedAt: DateTime(2026, 11, 19),
);

SpeedTestResult _result() => SpeedTestResult(
  ok: true,
  bytes: (12.3 * 1024 * 1024).round(),
  elapsed: const Duration(milliseconds: 1000),
);

SpeedSource? _usedSource;

Future<SpeedTestResult> _okSpeedTest(
  String node, {
  SpeedSourceChoice source = SpeedSourceChoice.defaultChoice,
  void Function(SpeedTestProgress progress)? onProgress,
  void Function(SpeedTestStage stage)? onStage,
  SpeedTestCancelToken? cancelToken,
}) async => _result();

Future<SpeedTestResult> _recordingSpeedTest(
  String node, {
  SpeedSourceChoice source = SpeedSourceChoice.defaultChoice,
  void Function(SpeedTestProgress progress)? onProgress,
  void Function(SpeedTestStage stage)? onStage,
  SpeedTestCancelToken? cancelToken,
}) async {
  _usedSource = source.source;
  return _result();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;
  late AppPrefs prefs;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('clashdeck_pulse');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          if (call.method.contains('ApplicationSupport')) return tmp.path;
          return null;
        });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Windows 上偶发文件仍被占用：测试结束清不掉临时目录不影响结论。
    }
  });

  Future<void> loadPrefs(WidgetTester tester) async {
    await tester.runAsync(() async {
      prefs = await AppPrefs.load();
    });
  }

  Widget host(Widget child) => MaterialApp(home: child);

  PulsePage page({
    Future<UpdateCheckResult> Function(String)? checkUpdate,
    Future<bool> Function(String)? openUrl,
    PulseSpeedTest? speedTest,
  }) => PulsePage(
    appVersion: '0.2.1',
    profileName: 'demo',
    profile: Profile.from(YamlDoc.parse(_yaml)),
    prefs: prefs,
    onClose: () {},
    checkUpdate: checkUpdate,
    openUrl: openUrl,
    speedTest: speedTest ?? _okSpeedTest,
  );

  testWidgets('右上角 × 会触发 onClose', (tester) async {
    await loadPrefs(tester);
    var closed = 0;
    await tester.pumpWidget(
      host(
        PulsePage(
          appVersion: '0.3.2',
          profileName: 'demo',
          profile: Profile.from(YamlDoc.parse(_yaml)),
          prefs: prefs,
          onClose: () => closed++,
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tap(find.byTooltip('收起'));
    await tester.pump();
    expect(closed, 1);
  });

  testWidgets('测速卡只列节点、单选，没有全选和延迟列表', (tester) async {
    await loadPrefs(tester);
    await tester.pumpWidget(host(page()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('节点测速'), findsOneWidget);
    expect(find.text('下载测速'), findsOneWidget);
    expect(find.text('测速线路'), findsOneWidget);
    expect(find.text('HK-01'), findsOneWidget);
    expect(find.text('JP-01'), findsOneWidget);
    expect(find.textContaining('全选'), findsNothing);
    expect(find.textContaining('上次结果'), findsNothing);
    expect(find.widgetWithText(FilledButton, '开始测速'), findsOneWidget);
  });

  testWidgets('测速完成显示单行结果，切换节点后清空', (tester) async {
    await loadPrefs(tester);
    await tester.pumpWidget(host(page()));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('开始测速'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('12.3 MB/s'), findsOneWidget);
    expect(find.textContaining('12 MB'), findsOneWidget);
    expect(find.textContaining('上次测速'), findsOneWidget);

    await tester.tap(find.text('JP-01'));
    await tester.pump();
    expect(find.textContaining('12.3 MB/s'), findsNothing);
  });

  testWidgets('切换线路会清空结果并按新线路请求', (tester) async {
    await loadPrefs(tester);
    _usedSource = null;
    await tester.pumpWidget(host(page(speedTest: _recordingSpeedTest)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('开始测速'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_usedSource, SpeedSource.fast);

    await tester.tap(find.text('Google'));
    await tester.pump();
    expect(find.textContaining('12.3 MB/s'), findsNothing);

    await tester.tap(find.text('开始测速'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(_usedSource, SpeedSource.google);
  });

  testWidgets('自定义地址非法时提示并禁用测速', (tester) async {
    await loadPrefs(tester);
    await tester.pumpWidget(host(page()));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('自定义'));
    await tester.pump();
    await tester.enterText(find.byType(AppTextField).last, 'not-a-url');
    await tester.pump();

    expect(find.text('只支持 http/https 地址'), findsWidgets);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, '开始测速'),
    );
    expect(button.onPressed, isNull);
  });

  testWidgets('测速中可取消，取消后不显示结果', (tester) async {
    await loadPrefs(tester);
    final completer = Completer<SpeedTestResult>();
    Future<SpeedTestResult> pending(
      String node, {
      SpeedSourceChoice source = SpeedSourceChoice.defaultChoice,
      void Function(SpeedTestProgress progress)? onProgress,
      void Function(SpeedTestStage stage)? onStage,
      SpeedTestCancelToken? cancelToken,
    }) => completer.future;

    await tester.pumpWidget(host(page(speedTest: pending)));
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('开始测速'));
    await tester.pump();
    expect(find.text('取消'), findsOneWidget);

    await tester.tap(find.text('取消'));
    await tester.pump();
    completer.complete(const SpeedTestResult(ok: false, cancelled: true));
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.textContaining('MB/s'), findsNothing);
    expect(find.text('开始测速'), findsOneWidget);
  });

  testWidgets('运行状态卡显示配置与出口', (tester) async {
    await loadPrefs(tester);
    await tester.pumpWidget(host(page()));
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.text('运行状态'), findsOneWidget);
    expect(find.text('当前配置'), findsOneWidget);
    expect(find.text('demo'), findsWidgets);
  });

  testWidgets('检查更新显示新版，去查看打开统一更新弹窗', (tester) async {
    await loadPrefs(tester);
    var opened = '';
    await tester.pumpWidget(
      host(
        page(
          checkUpdate: (_) async => UpdateAvailable(_info()),
          openUrl: (url) async {
            opened = url;
            return true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('检查更新').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.textContaining('发现 0.3.0'), findsOneWidget);
    await tester.tap(find.text('去查看'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('发现新版本'), findsOneWidget);
    await tester.tap(find.text('去下载'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(opened, contains('v0.3.0'));
  });

  testWidgets('点击图标或字标打开项目主页', (tester) async {
    await loadPrefs(tester);
    final opened = <String>[];
    await tester.pumpWidget(
      host(
        page(
          openUrl: (url) async {
            opened.add(url);
            return true;
          },
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byType(Image));
    await tester.tap(find.text('ClashDeck'));
    expect(opened, [clashDeckProjectUrl, clashDeckProjectUrl]);
  });

  testWidgets('已是最新版本时轻提示', (tester) async {
    await loadPrefs(tester);
    await tester.pumpWidget(
      host(page(checkUpdate: (_) async => UpToDate(_info()))),
    );
    await tester.pump(const Duration(milliseconds: 50));

    await tester.tap(find.text('检查更新').last);
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('已是最新版本'), findsWidgets);
  });
}
