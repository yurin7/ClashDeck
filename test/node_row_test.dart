import 'package:clashdeck/core/model/profile.dart';
import 'package:clashdeck/ui/widgets/node_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _node = ProxyEntry(
  index: 0,
  name: '香港 01',
  type: 'vless',
  raw: <String, Object?>{'name': '香港 01', 'type': 'vless'},
);

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('节点行显示名称、协议与延迟、当前徽章和菜单键', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 420,
          child: NodeRow(
            node: _node,
            delayText: '120 ms',
            selected: true,
            open: false,
            onOpenChanged: (_) {},
            onTap: () => taps++,
            onMenu: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    expect(find.text('香港 01'), findsOneWidget);
    expect(find.text('vless'), findsOneWidget);
    expect(find.text('120 ms'), findsOneWidget);
    expect(find.text('当前'), findsOneWidget);
    expect(find.byTooltip('节点操作'), findsOneWidget);

    await tester.tap(find.text('香港 01'));
    await tester.pump();
    expect(taps, 1);
  });

  testWidgets('未测速/超时文案直接透传', (tester) async {
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 420,
          child: NodeRow(
            node: _node,
            delayText: '超时',
            selected: false,
            open: false,
            onOpenChanged: (_) {},
            onTap: () {},
            onMenu: null,
            onDelete: () {},
          ),
        ),
      ),
    );
    expect(find.text('vless'), findsOneWidget);
    expect(find.text('超时'), findsOneWidget);
    expect(find.text('当前'), findsNothing);
    expect(find.byTooltip('节点操作'), findsNothing);
  });

  testWidgets('长按整行进入拖拽，不会误触编辑', (tester) async {
    var taps = 0;
    await tester.pumpWidget(
      _host(
        SizedBox(
          width: 420,
          child: NodeRow(
            node: _node,
            delayText: '—',
            selected: false,
            open: false,
            onOpenChanged: (_) {},
            onTap: () => taps++,
            onMenu: () {},
            onDelete: () {},
          ),
        ),
      ),
    );

    final gesture = await tester.startGesture(
      tester.getCenter(find.text('香港 01')),
    );
    await tester.pump(const Duration(milliseconds: 700));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(taps, 0);
  });

  testWidgets('左滑露出删除；点删除先收起再回调', (tester) async {
    final events = <String>[];
    var open = false;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _host(
          SizedBox(
            width: 420,
            child: NodeRow(
              node: _node,
              delayText: '—',
              selected: false,
              open: open,
              onOpenChanged: (value) {
                events.add('open:$value');
                setState(() => open = value);
              },
              onTap: () {},
              onMenu: () {},
              onDelete: () => events.add('delete'),
            ),
          ),
        ),
      ),
    );

    await tester.drag(find.text('香港 01'), const Offset(-120, 0));
    await tester.pumpAndSettle();
    expect(open, isTrue);
    expect(find.text('删除'), findsOneWidget);

    await tester.tap(find.text('删除'));
    await tester.pumpAndSettle();
    expect(events, ['open:true', 'open:false', 'delete']);
    expect(open, isFalse);
  });
}
