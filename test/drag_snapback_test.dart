import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/state/editor_state.dart';
import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/proxy_board.dart';
import 'package:clashdeck/ui/widgets/drag_state.dart';

const _yaml = '''
proxies:
  - {name: a, type: ss, server: 1.1.1.1, port: 1, cipher: aes-128-gcm, password: x}
  - {name: b, type: ss, server: 1.1.1.1, port: 2, cipher: aes-128-gcm, password: x}
proxy-groups:
  - {name: DEFAULT, type: select, proxies: [a, b]}
rules:
  - MATCH,DEFAULT
''';

void main() {
  tearDown(() => dragState.reset());

  testWidgets('被拒绝的拖拽结束后播放回弹，不数据改动、覆盖层收干净', (tester) async {
    final state = EditorState(doc: YamlDoc.parse(_yaml));
    final before = state.doc.text;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(height: 700, child: ProxyBoard(state: state)),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final baseChips = find.byType(NodeChip).evaluate().length;

    dragState.begin(
      node: 'a',
      group: 'DEFAULT',
      sourceRect: const Rect.fromLTWH(24, 360, 120, 36),
      feedbackSize: const Size(120, 36),
    );
    dragState.hintDuplicate('vip');
    // 拖到别的组被拒绝：结束时应回弹。
    expect(dragState.end(const Offset(420, 720)), isTrue);

    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    // 回弹浮层已经插进 Overlay。
    expect(find.byType(NodeChip).evaluate().length, baseChips + 1);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump();
    // 动画结束移除浮层，YAML 没变。
    expect(find.byType(NodeChip).evaluate().length, baseChips);
    expect(state.doc.text, before);
    expect(dragState.animating, isFalse);
    expect(dragState.duplicateGroup, isNull);
  });
}
