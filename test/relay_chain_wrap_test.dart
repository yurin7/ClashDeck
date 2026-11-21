import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/ui/widgets/relay_chain.dart';

const _long = 'very-long-node-name-abcdefghijkl';

String _yaml(List<String> nodes) {
  final proxies = nodes
      .map(
        (name) =>
            '  - {name: $name, type: ss, server: 1.1.1.1, port: 1, '
            'cipher: aes-128-gcm, password: x}',
      )
      .join('\n');
  final names = nodes.join(', ');
  return 'proxies:\n$proxies\n'
      'proxy-groups:\n'
      '  - {name: chain, type: relay, proxies: [$names]}\n'
      'rules:\n'
      '  - MATCH,chain\n';
}

/// 按指定卡宽渲染链条；延迟 + ⋮ + × 全开，复现真实组卡里的最宽组合。
Future<void> _pump(
  WidgetTester tester,
  List<String> nodes, {
  double width = 360,
  Map<String, int?> delays = const {},
}) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final profile = Profile.from(YamlDoc.parse(_yaml(nodes)));
  final group = profile.groupByName['chain']!;
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData.dark(useMaterial3: true),
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 800)),
        child: Scaffold(
          body: RelayChain(
            group: group,
            profile: profile,
            delays: delays,
            approx: const <String>{},
            onOpen: (_) {},
            onDelete: (_) {},
            onRemove: (_) {},
            onInsertAt: (node, index) {},
            onMoveLeft: (from, to) {},
            onMoveRight: (from, to) {},
            onMoveMember: (from, to) {},
            onAddMember: () {},
            onSelect: (_) {},
            onMenu: (node, index) {},
          ),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('长名在 360dp 下紧凑换行，连接线区域与加一阶仍在', (tester) async {
    await _pump(tester, const ['HK-01', 'JP-02', 'SG-04', _long]);
    expect(tester.takeException(), isNull);
    expect(find.text('加一阶'), findsOneWidget);
    final wrap = find.byType(Wrap);
    expect(tester.widget<Wrap>(wrap).spacing, lessThan(24));
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is CustomPaint &&
            widget.painter != null &&
            widget.child is Wrap,
      ),
      findsOneWidget,
    );
  });

  for (final width in const [320.0, 360.0]) {
    testWidgets('长名 + 延迟 + 菜单在 ${width.toInt()}dp 下不溢出', (tester) async {
      await _pump(
        tester,
        const [_long, 'JP-02', _long, 'SG-04'],
        width: width,
        delays: const {_long: 104, 'JP-02': 48},
      );
      expect(tester.takeException(), isNull);

      final name = tester.widget<Text>(find.text(_long).first);
      expect(name.overflow, TextOverflow.ellipsis);
      expect(name.maxLines, 1);
      expect(find.text('加一阶'), findsOneWidget);
    });
  }

  testWidgets('链条不再用横向滚动', (tester) async {
    await _pump(tester, const ['HK-01', 'JP-02', 'SG-04']);
    final scrollables = tester
        .widgetList<SingleChildScrollView>(find.byType(SingleChildScrollView))
        .where((s) => s.scrollDirection == Axis.horizontal);
    expect(scrollables, isEmpty);
    expect(find.byType(Wrap), findsOneWidget);
  });

  testWidgets('Wrap 子项 = 成员数 + 1（加一阶）', (tester) async {
    await _pump(tester, const ['HK-01', 'JP-02', 'SG-04']);
    final wrap = tester.widget<Wrap>(find.byType(Wrap));
    expect(wrap.children.length, 4);
  });
}
