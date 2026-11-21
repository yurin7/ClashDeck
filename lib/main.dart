import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'data/profile_store.dart';
import 'ui/app_shell.dart';
import 'ui/desktop_window.dart';
import 'ui/desktop_workspace.dart';
import 'ui/theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    final font = File.fromUri(
      File(Platform.resolvedExecutable).parent.uri
          .resolve('data/fonts/ResourceHanRoundedCN-Regular.ttf'),
    );
    try {
      await (FontLoader(
        kDesktopCjkFont,
      )..addFont(font.readAsBytes().then(ByteData.sublistView))).load();
    } on FileSystemException {
      // 调试构建没有复制字体时仍可使用 Windows 的系统字体。
    }
  }
  runApp(const ClashDeckApp());
}

class ClashDeckApp extends StatelessWidget {
  const ClashDeckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'ClashDeck',
      debugShowCheckedModeBanner: false,
      // 视觉以深色为基准，浅色是同一套系统的另一面。想让 App 跟随系统主题，
      // 把这里改成 ThemeMode.system 即可（两套配色都已定义）。
      themeMode: ThemeMode.dark,
      theme: ClashDeckTheme.light(),
      darkTheme: ClashDeckTheme.dark(),
      builder: Platform.isWindows
          ? (context, child) => Stack(
              fit: StackFit.expand,
              children: [
                ?child,
                const Positioned(
                  top: 0,
                  right: 0,
                  child: DesktopWindowCaption(),
                ),
              ],
            )
          : null,
      home: const _Bootstrap(),
    );
  }
}

/// 先把配置目录打开再进三页壳，避免每个页面各自去 open。
class _Bootstrap extends StatefulWidget {
  const _Bootstrap();

  @override
  State<_Bootstrap> createState() => _BootstrapState();
}

class _BootstrapState extends State<_Bootstrap> {
  late final Future<ProfileStore> _store = ProfileStore.open();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<ProfileStore>(
      future: _store,
      builder: (context, snapshot) {
        final store = snapshot.data;
        if (store != null) {
          if (Theme.of(context).platform == TargetPlatform.windows) {
            return DesktopWorkspace(store: store);
          }
          return AppShell(store: store);
        }
        if (snapshot.hasError) {
          return Scaffold(
            body: Center(
              child: Padding(
                padding: const EdgeInsets.all(Insets.xl),
                child: Text('打开配置目录失败：${snapshot.error}'),
              ),
            ),
          );
        }
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      },
    );
  }
}
