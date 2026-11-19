import 'package:clashdeck/ui/settings_dns_switch.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// DNS 不强制：TUN 下也能关，只在关闭时提醒一次，不阻止回写。
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

  testWidgets('TUN 下可以关闭，弹一次提醒并回写 false', (tester) async {
    var calls = 0;
    bool? value;
    await pumpSwitch(
      tester,
      tun: true,
      enabled: true,
      onChanged: (v) {
        calls++;
        value = v;
      },
    );

    final tile = find.byType(SwitchListTile);
    expect(tester.widget<SwitchListTile>(tile).value, isTrue);

    await tester.tap(tile);
    await tester.pump();

    expect(find.text('关闭 DNS 后 TUN 内域名可能无法解析，排障时可重新打开'), findsOneWidget);
    expect(calls, 1);
    expect(value, isFalse);
  });

  testWidgets('仅端口模式直接关闭、不弹提醒', (tester) async {
    var calls = 0;
    await pumpSwitch(
      tester,
      tun: false,
      enabled: true,
      onChanged: (_) => calls++,
    );

    await tester.tap(find.byType(SwitchListTile));
    await tester.pump();

    expect(find.textContaining('关闭 DNS 后'), findsNothing);
    expect(calls, 1);
  });

  testWidgets('开关显示配置里的真实值（不强制 true）', (tester) async {
    await pumpSwitch(tester, tun: true, enabled: false, onChanged: (_) {});
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile)).value,
      isFalse,
    );
  });
}
