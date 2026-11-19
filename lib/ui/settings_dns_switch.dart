import 'package:material_ui/material_ui.dart';

import 'theme.dart';
import 'widgets.dart';

/// 「启用 DNS」开关。
///
/// TUN 模式下强制显示为开启并拒绝关闭：VpnService 把系统 DNS 指到
/// 198.18.0.2，`dns-hijack` 依赖内核 DNS；关掉后域名解析全废，但延迟
/// 测速（走 REST）仍然正常，极难自查。要关闭只能切到「仅代理端口」。
class DnsEnabledSwitch extends StatelessWidget {
  const DnsEnabledSwitch({
    super.key,
    required this.tun,
    required this.enabled,
    required this.onEnabledChanged,
  });

  /// 当前是否 TUN 模式（TUN 下锁死为开启）。
  final bool tun;

  /// 配置里真实的 `dns.enable`。
  final bool enabled;

  final ValueChanged<bool> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      value: tun ? true : enabled,
      onChanged: (value) {
        if (tun && !value) {
          showToast(context, 'TUN 模式必须开启 DNS；要关闭请切到「仅代理端口」模式');
          return;
        }
        onEnabledChanged(value);
      },
      contentPadding: const EdgeInsets.fromLTRB(0, 0, Insets.md, 0),
      title: Text('启用 DNS', style: display(14, weight: 600)),
      subtitle: Text(
        tun ? 'TUN 模式强制开启：域名解析依赖内核 DNS，关掉会静默断域名' : '仅代理端口模式可关闭；TUN 模式下会被强制开启',
        style: hintStyle(context),
      ),
    );
  }
}
