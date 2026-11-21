import 'dart:async';
import 'dart:io';

import 'package:clashdeck/core/update/update_check.dart';
import 'package:clashdeck/runtime/android_update.dart';
import 'package:clashdeck/ui/update_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

UpdateInfo _info({UpdateApk? apk}) => UpdateInfo(
  version: '0.2.2',
  url: 'https://github.com/yurin7/ClashDeck/releases/tag/v0.2.2',
  notes: '- 修复 A\n- 修复 B\n- 新增 C',
  publishedAt: DateTime(2026, 11, 19),
  androidApks: {'x86_64': ?apk},
);

class _TestInstaller extends AndroidUpdateInstaller {
  final package = UpdateApk(
    name: 'ClashDeck-0.2.2-x86_64.apk',
    url: Uri.parse(
      '$clashDeckProjectUrl/releases/download/v0.2.2/ClashDeck-0.2.2-x86_64.apk',
    ),
    size: 1024,
  );
  final transfer = Completer<File>();
  var downloads = 0;
  var installs = 0;
  var settingsOpened = 0;
  var allowed = false;

  @override
  Future<UpdateApk?> selectApk(UpdateInfo info) async =>
      info.androidApks['x86_64'];

  @override
  Future<File> download(
    UpdateApk apk, {
    required HttpClient client,
    required void Function(double progress) onProgress,
  }) {
    downloads++;
    onProgress(0.5);
    return transfer.future;
  }

  @override
  Future<bool> openInstaller(File apk) async {
    installs++;
    return allowed;
  }

  @override
  Future<void> openInstallSettings() async {
    settingsOpened++;
  }
}

void main() {
  Future<void> pumpHost(
    WidgetTester tester, {
    required Future<bool> Function(String) openUrl,
    void Function(bool?)? onResult,
    _TestInstaller? installer,
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
                    _info(apk: installer?.package),
                    openUrl: openUrl,
                    installer: installer,
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

  testWidgets('下载后打开安装授权，返回后继续使用同一安装包', (tester) async {
    final installer = _TestInstaller();
    bool? result;
    await pumpHost(
      tester,
      openUrl: (_) async => throw StateError('Unexpected external URL'),
      installer: installer,
      onResult: (value) => result = value,
    );
    await tester.tap(find.text('下载并安装'));
    await tester.pumpAndSettle();
    expect(find.text('已下载 50%'), findsOneWidget);

    installer.transfer.complete(File(installer.package.name));
    await tester.pumpAndSettle();
    expect(find.text('允许安装'), findsOneWidget);
    expect(installer.installs, 1);

    await tester.tap(find.text('允许安装'));
    await tester.pump();
    expect(installer.settingsOpened, 1);
    installer.allowed = true;
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(installer.downloads, 1);
    expect(installer.installs, 2);
    expect(result, isTrue);
    expect(find.text('发现新版本'), findsNothing);
  });

  testWidgets('关闭下载弹窗后，已完成的下载不会拉起安装界面', (tester) async {
    final installer = _TestInstaller()..allowed = true;
    await pumpHost(tester, openUrl: (_) async => true, installer: installer);
    await tester.tap(find.text('下载并安装'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('取消'));
    installer.transfer.complete(File(installer.package.name));
    await tester.pumpAndSettle();
    expect(installer.installs, 0);
    expect(find.text('打开'), findsOneWidget);
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
