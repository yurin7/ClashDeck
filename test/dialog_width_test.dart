import 'package:clashdeck/data/profile_store.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/app_dialog.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/rules/rule_row_card.dart';
import 'package:clashdeck/ui/rules_tab.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 800 宽（平板/桌面）上应该卡在 520；手机 360 上应该是 296。
Future<double> _widthFor(WidgetTester tester, double width) async {
  late double out;
  await tester.pumpWidget(
    MaterialApp(
      home: MediaQuery(
        data: MediaQueryData(size: Size(width, 640)),
        child: Builder(
          builder: (context) {
            out = dialogWidthOf(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    ),
  );
  return out;
}

EditorState _state() => EditorState.fromText(
  ProfileStore.starterConfig(name: 't'),
  fileName: 't.yaml',
);

void main() {
  group('dialogWidthOf', () {
    testWidgets('宽屏卡在 520', (tester) async {
      expect(await _widthFor(tester, 800), 520);
      expect(await _widthFor(tester, 1000), 520);
    });

    testWidgets('手机宽度减 64', (tester) async {
      expect(await _widthFor(tester, 360), 296);
      expect(await _widthFor(tester, 320), 256);
    });
  });

  testWidgets('业务弹窗宽度一致', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _state();
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, _) => RulesTab(state: state),
          ),
        ),
      ),
    );

    // 1) 先打开规则详情，再进编辑规则：两个弹窗都受同一宽度约束。
    await tester.tap(find.byType(RuleRowCard).first);
    await tester.pumpAndSettle();
    expect(find.text('规则详情'), findsOneWidget);
    final detailWidth = tester
        .getSize(find.byKey(const ValueKey('edit-dialog')))
        .width;
    await tester.tap(find.text('编辑'));
    await tester.pumpAndSettle();
    final ruleWidth = tester
        .getSize(find.byKey(const ValueKey('edit-dialog')))
        .width;
    final ruleFieldHeight = tester.getSize(find.byType(TextField).first).height;
    await tester.tap(find.byTooltip('关闭'));
    await tester.pumpAndSettle();
    expect(detailWidth, ruleWidth);

    final expected = dialogWidthOf(tester.element(find.byType(RulesTab)));

    // 3) 新建策略组（换到代理页）
    final proxyState = _state();
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: proxyState,
            builder: (_, _) => ProxyBoard(state: proxyState),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('新建组'));
    await tester.tap(find.text('新建组'));
    await tester.pumpAndSettle();
    final groupWidth = tester
        .getSize(find.byKey(const ValueKey('edit-dialog')))
        .width;
    final groupFieldHeight = tester
        .getSize(find.byType(TextField).first)
        .height;
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    expect(ruleWidth, expected);
    expect(groupWidth, expected);
    expect(groupFieldHeight, closeTo(ruleFieldHeight, 1));
    expect(ruleFieldHeight, lessThan(60));
  });

  testWidgets('搜索框与表单输入框同样高', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final state = _state();
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.dark(),
        home: Scaffold(
          body: ListenableBuilder(
            listenable: state,
            builder: (_, _) => ProxyBoard(state: state),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('添加成员').first);
    await tester.pumpAndSettle();
    final searchHeight = tester.getSize(find.byType(TextField).first).height;
    await tester.tap(find.text('取消'));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('新建组'));
    await tester.tap(find.text('新建组'));
    await tester.pumpAndSettle();
    final nameHeight = tester.getSize(find.byType(TextField).first).height;

    expect(searchHeight, closeTo(nameHeight, 1));
  });
}
