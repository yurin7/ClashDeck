import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/widgets/target_selector_field.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/sheets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

const String _cfg = '''
mixed-port: 7890
proxies:
  - name: n1
    type: ss
    server: 1.2.3.4
    port: 8388
    cipher: aes-128-gcm
    password: pw
  - name: n2
    type: ss
    server: 5.6.7.8
    port: 8388
    cipher: aes-128-gcm
    password: pw
proxy-groups:
  - name: PROXY
    type: select
    proxies:
      - n1
rules:
  - MATCH,PROXY
''';

class _Harness extends StatelessWidget {
  const _Harness({required this.open});

  final Future<void> Function(BuildContext context) open;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(
          builder: (inner) => Center(
            child: FilledButton(
              onPressed: () => open(inner),
              child: const Text('打开'),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> _open(
  WidgetTester tester,
  Future<void> Function(BuildContext) open,
) async {
  await tester.pumpWidget(_Harness(open: open));
  await tester.tap(find.text('打开'));
  await tester.pumpAndSettle();
}

void _sizeScreen(
  WidgetTester tester, {
  required double logicalWidth,
  required double logicalHeight,
}) {
  tester.view.physicalSize = Size(logicalWidth * 2, logicalHeight * 2);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
}

double _expectedMax({required double logicalHeight}) {
  final cap = logicalHeight * 0.72;
  return cap > 640 ? 640 : cap;
}

void main() {
  testWidgets('菜单型 sheet（无标题）不超高，内容多时内部滚动', (tester) async {
    _sizeScreen(tester, logicalWidth: 540, logicalHeight: 1200);
    await _open(
      tester,
      (context) => showAppSheet<void>(
        context,
        body: (ctx) => ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < 40; i++)
              ListTile(dense: true, title: Text('条目 $i')),
          ],
        ),
      ),
    );

    expect(find.byTooltip('关闭'), findsNothing);
    final height = tester.getSize(find.byType(BottomSheet)).height;
    expect(height, lessThanOrEqualTo(_expectedMax(logicalHeight: 1200) + 1));
  });

  testWidgets('小屏（360×640）按 72% 缩，不超高', (tester) async {
    _sizeScreen(tester, logicalWidth: 360, logicalHeight: 640);
    await _open(
      tester,
      (context) => showAppSheet<void>(
        context,
        body: (ctx) => ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < 40; i++)
              ListTile(dense: true, title: Text('条目 $i')),
          ],
        ),
      ),
    );

    final height = tester.getSize(find.byType(BottomSheet)).height;
    expect(height, lessThanOrEqualTo(_expectedMax(logicalHeight: 640) + 1));
  });

  testWidgets('内容型 sheet：标题行固定、底部按钮常驻、可关闭', (tester) async {
    _sizeScreen(tester, logicalWidth: 540, logicalHeight: 1200);
    var tapped = false;
    await _open(
      tester,
      (context) => showAppSheet<void>(
        context,
        title: '选择要加入的节点',
        subtitle: '向「PROXY」批量添加成员',
        body: (ctx) => ListView(
          shrinkWrap: true,
          children: [
            for (var i = 0; i < 40; i++)
              ListTile(dense: true, title: Text('候选 $i')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => tapped = true, child: const Text('确定')),
        ],
      ),
    );

    expect(find.text('选择要加入的节点'), findsOneWidget);
    expect(find.text('向「PROXY」批量添加成员'), findsOneWidget);
    expect(find.text('确定'), findsOneWidget);
    expect(
      tester.getSize(find.byType(BottomSheet)).height,
      lessThanOrEqualTo(641),
    );

    await tester.tap(find.text('确定'));
    expect(tapped, isTrue);
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets('添加成员 sheet 不超过屏高 72%', (tester) async {
    _sizeScreen(tester, logicalWidth: 540, logicalHeight: 2400);
    final state = EditorState.fromText(_cfg, fileName: 't.yaml');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProxyBoard(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加成员').first);
    await tester.pumpAndSettle();

    expect(find.text('选择要加入的节点'), findsOneWidget);
    final height = tester.getSize(find.byType(BottomSheet)).height;
    expect(height, lessThanOrEqualTo(_expectedMax(logicalHeight: 2400) + 1));
  });

  testWidgets('添加节点方式 sheet 不超过屏高 72%', (tester) async {
    _sizeScreen(tester, logicalWidth: 540, logicalHeight: 2400);
    final state = EditorState.fromText(_cfg, fileName: 't.yaml');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ProxyBoard(state: state)),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加节点').first);
    await tester.pumpAndSettle();

    expect(find.text('手动填写'), findsOneWidget);
    final height = tester.getSize(find.byType(BottomSheet)).height;
    expect(height, lessThanOrEqualTo(_expectedMax(logicalHeight: 2400) + 1));
  });

  testWidgets('GLOBAL 选择面板（showTargetPickerSheet）不超过屏高 72%', (tester) async {
    _sizeScreen(tester, logicalWidth: 540, logicalHeight: 2400);
    await _open(
      tester,
      (context) => showTargetPickerSheet(
        context,
        title: 'GLOBAL 走哪个节点',
        options: [for (var i = 0; i < 40; i++) 'n$i'],
      ),
    );

    final height = tester.getSize(find.byType(BottomSheet)).height;
    expect(height, lessThanOrEqualTo(_expectedMax(logicalHeight: 2400) + 1));
  });
}
