import 'package:clashdeck/ui/settings_dns_switch.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// TUN 模式下 DNS 被强制开启：设置页不能把 `dns.enable` 写成 false，
/// 否则运行配置里的 `dns-hijack` 会失效、域名全部解析失败。
void main() {
  Future<void> pumpSwitch(
    WidgetTester tester, {
    required bool tun,
    required bool enabled,
    required ValueChanged<bool> onChanged,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: Scaffold(
          body: DnsEnabledSwitch(
            tun: tun,
            enabled: enabled,
            onEnabledChanged: onChanged,
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('TUN 下点关闭被拦下并提示，不回写 false', (tester) async {
    var calls = 0;
    await pumpSwitch(
      tester,
      tun: true,
      enabled: false,
      onChanged: (_) => calls++,
    );

    final tile = find.byType(SwitchListTile);
    expect(tile, findsOneWidget);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pump();

    expect(find.text('TUN 模式必须开启 DNS；要关闭请切到「仅代理端口」模式'), findsOneWidget);
    expect(calls, 0);
  });

  testWidgets('仅端口模式允许关闭并回写', (tester) async {
    var value = true;
    await pumpSwitch(
      tester,
      tun: false,
      enabled: true,
      onChanged: (v) => value = v,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(value, isFalse);
  });
}
