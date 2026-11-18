import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _node = ProxyEntry(
  index: 0,
  name: '香港 01',
  type: 'vless',
  raw: {
    'name': '香港 01',
    'type': 'vless',
    'server': 'hk.example.com',
    'port': 443,
  },
);

RuleEntry _rule(String raw, int index) => RuleEntry.parse(index, raw);

Future<void> _pump(WidgetTester tester, Widget child) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: ClashDeckTheme.dark(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Padding(padding: const EdgeInsets.all(12), child: child),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('四类胶囊：节点 / 规则 / 组 / 系统策略各有自己的外壳', (tester) async {
    await _pump(
      tester,
      Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          NodeChip(
            node: _node,
            fromGroup: 'PROXY',
            onOpen: () {},
            onMove: () {},
            onDelete: () {},
            onRemove: null,
          ),
          RuleChip(
            rule: _rule('DOMAIN-SUFFIX,a.com,PROXY', 0),
            onTap: () {},
            onDelete: () {},
          ),
          const GroupChip(name: 'PROXY', members: 3),
          const SystemPolicyChip(name: 'DIRECT'),
          const SystemPolicyChip(name: 'REJECT'),
          const SystemPolicyChip(name: 'REJECT-DROP', note: '不常用'),
        ],
      ),
    );

    expect(find.byType(NodeChip), findsOneWidget);
    expect(find.byType(RuleChip), findsOneWidget);
    expect(find.byType(GroupChip), findsOneWidget);
    expect(find.byType(SystemPolicyChip), findsNWidgets(3));

    // 节点胶囊：协议字母 + 名字。
    expect(find.text('V'), findsOneWidget);
    expect(find.text('香港 01'), findsOneWidget);

    // 规则胶囊：可认的名字 + 箭头目标。
    expect(find.text('a.com'), findsOneWidget);
    expect(find.text('→ PROXY'), findsOneWidget);

    // 组胶囊：成员数和使用次要色系的组图标。
    expect(find.text('PROXY'), findsOneWidget);
    expect(find.text('3 成员'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(GroupChip),
        matching: find.byIcon(Icons.radio_button_checked),
      ),
      findsOneWidget,
    );

    // 系统策略胶囊：各自的图标 + REJECT-DROP 的「不常用」。
    expect(
      find.descendant(
        of: find.byType(SystemPolicyChip),
        matching: find.byIcon(Icons.arrow_outward),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SystemPolicyChip),
        matching: find.byIcon(Icons.block),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byType(SystemPolicyChip),
        matching: find.byIcon(Icons.bolt),
      ),
      findsOneWidget,
    );
    expect(find.text('不常用'), findsOneWidget);
  });

  testWidgets('系统策略配色：DIRECT 绿、REJECT 红、REJECT-DROP 灰', (tester) async {
    final scheme = ClashDeckTheme.dark().colorScheme;
    expect(systemPolicyColor('DIRECT', scheme), scheme.tertiary);
    expect(systemPolicyColor('REJECT', scheme), scheme.error);
    expect(systemPolicyColor('REJECT-DROP', scheme), scheme.onSurfaceVariant);

    await _pump(
      tester,
      const Wrap(
        spacing: 8,
        children: [
          SystemPolicyChip(name: 'DIRECT'),
          SystemPolicyChip(name: 'REJECT'),
          SystemPolicyChip(name: 'REJECT-DROP'),
        ],
      ),
    );

    Color? labelColor(String name) {
      final text = tester.widget<Text>(
        find.descendant(
          of: find.byType(SystemPolicyChip),
          matching: find.text(name),
        ),
      );
      return text.style?.color;
    }

    expect(labelColor('DIRECT'), scheme.tertiary);
    expect(labelColor('REJECT'), scheme.error);
    expect(labelColor('REJECT-DROP'), scheme.onSurfaceVariant);
  });

  testWidgets('名称胶囊：选中只有紫底紫边、禁用变灰、点按回调', (tester) async {
    var taps = 0;
    await _pump(
      tester,
      Wrap(
        spacing: 8,
        children: [
          NameChip(
            name: 'PROXY',
            icon: Icons.account_tree_outlined,
            selected: true,
            onTap: () => taps++,
          ),
          const NameChip(name: '香港 01', enabled: false),
          const NameChip(name: 'DIRECT', subtitle: '系统策略'),
        ],
      ),
    );

    expect(find.text('PROXY'), findsOneWidget);
    expect(find.text('香港 01'), findsOneWidget);
    expect(find.text('系统策略'), findsOneWidget);
    expect(find.byIcon(Icons.check), findsNothing);

    await tester.tap(find.text('PROXY'));
    expect(taps, 1);

    // 禁用项不触发（它没有 onTap，点击不会抛异常也不会计数）。
    await tester.tap(find.text('香港 01'));
    expect(taps, 1);
  });
}
