import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/ui/widgets/relay_chain.dart';

Profile _profile(List<String> members) => Profile.from(
  YamlDoc.parse('''
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 1, cipher: aes-128-gcm, password: x}
  - {name: b, type: ss, server: 1.1.1.1, port: 2, cipher: aes-128-gcm, password: x}
  - {name: c, type: ss, server: 1.1.1.1, port: 3, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: chain, type: relay, proxies: [${members.join(', ')}]}
rules:
  - MATCH,chain
'''),
);

Widget _app(Profile profile, {VoidCallback? onAddMember}) {
  final group = profile.groups.single;
  return MaterialApp(
    home: Scaffold(
      body: RelayChain(
        group: group,
        profile: profile,
        delays: const {},
        approx: const {},
        selectedName: null,
        onOpen: (_) {},
        onDelete: (_) {},
        onRemove: (_) {},
        onInsertAt: (_, _) {},
        onMoveLeft: (_, _) {},
        onMoveRight: (_, _) {},
        onAddMember: onAddMember ?? () {},
      ),
    ),
  );
}

void main() {
  testWidgets('少于两阶时给出说明和添加入口', (tester) async {
    final profile = _profile(['a']);
    var added = false;
    await tester.pumpWidget(_app(profile, onAddMember: () => added = true));

    expect(find.textContaining('链式代理至少需要 2 个节点'), findsOneWidget);
    // 空态仍然保留「加一阶」入口。
    expect(find.text('加一阶'), findsOneWidget);
    await tester.tap(find.text('加一阶'));
    expect(added, isTrue);
  });

  testWidgets('三阶链条按顺序显示，阶间有箭头，末尾有加一阶', (tester) async {
    await tester.pumpWidget(_app(_profile(['a', 'b', 'c'])));

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
    expect(find.text('c'), findsOneWidget);
    // 序号徽标。
    expect(find.text('1'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    // 三阶之间两个箭头。
    expect(find.byIcon(Icons.arrow_right_alt_rounded), findsNWidgets(2));
    expect(find.text('加一阶'), findsOneWidget);
  });

  testWidgets('链条满两阶以上时点「加一阶」仍能触发 onAddMember', (tester) async {
    var added = 0;
    await tester.pumpWidget(
      _app(_profile(['a', 'b', 'c']), onAddMember: () => added++),
    );

    await tester.tap(find.text('加一阶'));
    await tester.pump();
    expect(added, 1);
  });
}
