import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'widgets.dart';

/// 「启用 DNS」开关。
///
/// 不做任何强制：TUN 模式下也可以关闭。关闭时系统 DNS 会指向
/// 198.18.0.2，但没有内核 DNS 应答，域名可能无法解析（延迟测试仍正常），
/// 因此在 TUN 模式下关闭时给一次非阻塞提醒，方便排障时快速找回。
class DnsEnabledSwitch extends StatelessWidget {
  const DnsEnabledSwitch({
    super.key,
    required this.tun,
    required this.enabled,
    required this.onEnabledChanged,
  });

  /// 当前是否 TUN 模式（只影响关闭时的提醒文案）。
  final bool tun;

  /// 配置里真实的 `dns.enable`。
  final bool enabled;

  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: enabled,
      onChanged: (value) {
        if (tun && !value) {
          showToast(context, '关闭 DNS 后 TUN 内域名可能无法解析，排障时可重新打开');
        }
        onEnabledChanged(value);
      },
      contentPadding: const EdgeInsets.fromLTRB(Insets.lg, 0, Insets.md, 0),
      title: Text('启用 DNS', style: display(14, weight: 600)),
      subtitle: Text('域名解析依赖内核 DNS，关闭后可能无法解析域名', style: hintStyle(context)),
    );
  }
}
