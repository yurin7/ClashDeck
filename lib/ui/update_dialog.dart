import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/update/update_check.dart';
import '../runtime/android_update.dart';
import 'app_dialog.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets/edit_dialog.dart';

/// 「发现新版本」弹窗：Android 可下载并发起安装，其余情况打开发布页。
Future<bool> showUpdateDialog(
  BuildContext context,
  UpdateInfo info, {
  Future<bool> Function(String url)? openUrl,
  AndroidUpdateInstaller? installer,
}) async {
  final updater =
      installer ?? (Platform.isAndroid ? const AndroidUpdateInstaller() : null);
  UpdateApk? apk;
  if (updater != null && info.androidApks.isNotEmpty) {
    try {
      apk = await updater.selectApk(info);
    } on PlatformException {
      // 查询不到 ABI 时，可从发布页手动选择安装包。
    } on MissingPluginException {
      // 平台暂时没有安装入口。
    }
  }
  if (!context.mounted) return false;
  final opened = await showAppDialog<bool>(
    context,
    width: dialogWidthOf(context),
    builder: (ctx) {
      final package = apk;
      if (package != null && updater != null) {
        return _InstallUpdateDialog(
          info: info,
          apk: package,
          installer: updater,
        );
      }
      return EditDialog(
        title: '发现新版本',
        subtitle: '当前 ${info.version} 已发布',
        confirmLabel: '去下载',
        cancelLabel: '取消',
        content: _UpdateBody(info: info),
        onCancel: () => Navigator.pop(ctx, false),
        onConfirm: () async {
          final launcher =
              openUrl ??
              (url) => launchUrl(
                Uri.parse(url),
                mode: LaunchMode.externalApplication,
              );
          final ok = info.url.isEmpty ? false : await launcher(info.url);
          if (ctx.mounted) Navigator.pop(ctx, ok);
        },
      );
    },
  );
  return opened ?? false;
}

class _InstallUpdateDialog extends StatefulWidget {
  const _InstallUpdateDialog({
    required this.info,
    required this.apk,
    required this.installer,
  });

  final UpdateInfo info;
  final UpdateApk apk;
  final AndroidUpdateInstaller installer;

  @override
  State<_InstallUpdateDialog> createState() => _InstallUpdateDialogState();
}

class _InstallUpdateDialogState extends State<_InstallUpdateDialog> {
  late final AppLifecycleListener _lifecycle;
  HttpClient? _client;
  File? _downloaded;
  int? _progress;
  String? _error;
  bool _busy = false;
  bool _needsPermission = false;
  bool _waitingForSettings = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onResume: () {
        if (!_waitingForSettings) return;
        _waitingForSettings = false;
        unawaited(_install());
      },
    );
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    _client?.close(force: true);
    super.dispose();
  }

  Future<void> _install() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
      if (_downloaded == null) _progress = 0;
    });
    try {
      if (_downloaded == null) {
        final client = HttpClient();
        _client = client;
        try {
          _downloaded = await widget.installer.download(
            widget.apk,
            client: client,
            onProgress: (progress) {
              final percent = (progress * 100).floor();
              if (mounted && percent != _progress) {
                setState(() => _progress = percent);
              }
            },
          );
        } finally {
          client.close(force: true);
          _client = null;
        }
      }
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      final opened = await widget.installer.openInstaller(_downloaded!);
      if (!mounted || ModalRoute.of(context)?.isCurrent != true) return;
      if (opened) {
        Navigator.of(context).pop(true);
      } else {
        _needsPermission = true;
      }
    } catch (error) {
      _needsPermission = false;
      _downloaded = null;
      _error = switch (error) {
        PlatformException(:final message) => message ?? '无法打开 Android 安装程序',
        FormatException(:final message) => message,
        _ => '下载安装包失败，请重试',
      };
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _progress = null;
        });
      }
    }
  }

  Future<void> _requestPermission() async {
    setState(() {
      _waitingForSettings = true;
      _error = null;
    });
    try {
      await widget.installer.openInstallSettings();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _waitingForSettings = false;
        _error = '无法打开安装授权设置';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = _progress;
    final message =
        _error ?? (_needsPermission ? '请允许 ClashDeck 安装应用，返回后继续更新。' : null);
    return EditDialog(
      title: '发现新版本',
      confirmLabel: _busy
          ? (progress == null ? '正在准备…' : '下载中…')
          : _needsPermission
          ? '允许安装'
          : '下载并安装',
      onConfirm: _busy || _waitingForSettings
          ? null
          : _needsPermission
          ? _requestPermission
          : _install,
      content: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _UpdateBody(info: widget.info),
          MotionSize(
            child: progress != null || message != null
                ? Padding(
                    padding: const EdgeInsets.only(top: Insets.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (progress != null) ...[
                          LinearProgressIndicator(value: progress / 100),
                          const SizedBox(height: Insets.xs),
                          Text('已下载 $progress%', style: hintStyle(context)),
                        ] else
                          Text(message!, style: hintStyle(context)),
                      ],
                    ),
                  )
                : const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

class _UpdateBody extends StatelessWidget {
  const _UpdateBody({required this.info});

  final UpdateInfo info;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final date = info.publishedAt;
    final dateLabel = date == null
        ? null
        : '${date.year}-${_two(date.month)}-${_two(date.day)}';
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: Insets.sm,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(Radiuses.chip.x),
              ),
              child: Text(
                'v${info.version}',
                style: display(13, weight: 700, color: scheme.primary),
              ),
            ),
            if (dateLabel != null) ...[
              const SizedBox(width: Insets.sm),
              Text(dateLabel, style: hintStyle(context)),
            ],
          ],
        ),
        const SizedBox(height: Insets.md),
        // 纯文本、最多 6 行高，超出在框内滚动（不随弹窗变高）。
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 132),
          child: Scrollbar(
            child: SingleChildScrollView(
              child: Text(info.notes.isEmpty ? '这次没有写更新说明。' : info.notes),
            ),
          ),
        ),
      ],
    );
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
