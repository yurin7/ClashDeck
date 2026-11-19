import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import '../core/edit/config_ops.dart';
import '../core/model/app_settings.dart';
import '../runtime/runtime_controller.dart';
import '../state/settings_state.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/edit_dialog.dart';

/// 生成给用户/作者排查用的诊断文本。
///
/// 只读、纯 Dart：版本、代理模式、分流模式、全局出口、应用路由、DNS/TUN
/// 关键项和最后 20 行日志。不包含节点密码、订阅地址等敏感信息。
String buildRuntimeDiagnostic({
  required String appVersion,
  required RuntimeController runtime,
  required SettingsState? settings,
}) {
  final doc = runtime.configProvider();
  final dnsRaw = doc.plainAt(['dns', 'enable']);
  final dns = dnsRaw == null
      ? '未设置（TUN 下强制开启）'
      : (dnsRaw == true ? 'true' : 'false');
  final tunStack =
      settings?.tunStack ??
      (doc.plainAt(['tun', 'stack']) as String?)?.trim() ??
      'gvisor';
  final docMtu = doc.plainAt(['tun', 'mtu']);
  final tunMtu = settings?.tunMtu ?? (docMtu is num ? docMtu.toInt() : 9000);
  final mode =
      settings?.mode ?? (doc.plainAt(['mode']) as String?)?.trim() ?? 'rule';
  final groups = doc.plainAt(['proxy-groups']);
  String? defaultExit;
  if (groups is List) {
    for (final raw in groups) {
      if (raw is! Map || raw['name'] != kDefaultGroupName) continue;
      final members =
          (raw['proxies'] as List?)?.whereType<String>().toList(
            growable: false,
          ) ??
          const <String>[];
      final saved = settings?.app.groupNodes[kDefaultGroupName];
      defaultExit = saved != null && members.contains(saved)
          ? saved
          : (members.isEmpty ? null : members.first);
      break;
    }
  }
  final tunEstablished = runtime.serviceRunning ? '是（VpnService 运行中）' : '否';
  final traffic = '↑${_bytes(runtime.up)} ↓${_bytes(runtime.down)}';
  final lines = runtime.logs.length > 20
      ? runtime.logs.sublist(runtime.logs.length - 20)
      : runtime.logs;

  final buffer = StringBuffer()
    ..writeln('ClashDeck ${appVersion.isEmpty ? '（未知版本）' : appVersion}')
    ..writeln('运行模式：${settings?.app.proxyMode.label ?? '—'}')
    ..writeln('分流模式：$mode')
    ..writeln('全局出口：${settings?.app.globalNode ?? '—'}')
    ..writeln('DEFAULT 当前出口：${defaultExit ?? '—'}')
    ..writeln('应用路由：${settings?.app.routeMode.label ?? '—'}')
    ..writeln('dns.enable：$dns')
    ..writeln('TUN stack：$tunStack')
    ..writeln('TUN mtu：$tunMtu')
    ..writeln('TUN 已建立：$tunEstablished')
    ..writeln('最后错误：${runtime.lastError ?? '—'}')
    ..writeln('代理流量：$traffic')
    ..writeln('—— 日志（最后 ${lines.length} 行）——');
  if (lines.isEmpty) {
    buffer.writeln('（暂无日志）');
  } else {
    for (final line in lines) {
      buffer.writeln(line);
    }
  }
  return buffer.toString();
}

String _bytes(int value) {
  if (value < 1024) return '${value}B';
  final kb = value / 1024;
  if (kb < 1024) return '${kb.toStringAsFixed(1)}KB';
  return '${(kb / 1024).toStringAsFixed(2)}MB';
}

/// 内核日志卡「诊断」入口：显示 [buildRuntimeDiagnostic] 的内容并可复制。
Future<void> showRuntimeDiagnosticDialog(
  BuildContext context, {
  required String appVersion,
  required RuntimeController runtime,
  required SettingsState? settings,
}) {
  final report = buildRuntimeDiagnostic(
    appVersion: appVersion,
    runtime: runtime,
    settings: settings,
  );
  return showAppDialog<void>(
    context,
    width: dialogWidthOf(context),
    builder: (ctx) => EditDialog(
      title: '诊断信息',
      subtitle: '给作者排查用，不含节点密码与订阅地址',
      confirmLabel: '关闭',
      showCancel: false,
      onConfirm: () => Navigator.pop(ctx),
      actions: [
        TextButton.icon(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: report));
            if (!ctx.mounted) return;
            showToast(ctx, '已复制');
          },
          icon: const Icon(Icons.copy_rounded, size: 18),
          label: const Text('复制'),
        ),
      ],
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 380),
        child: SingleChildScrollView(
          child: Text(report, style: monoStyle(ctx, size: 11.5)),
        ),
      ),
    ),
  );
}
