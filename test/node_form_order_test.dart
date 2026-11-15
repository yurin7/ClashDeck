import 'package:clashdeck/ui/node_form_page.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// 打开节点表单，保存后把 pop 出来的 Map 抓回来。
class _Host extends StatefulWidget {
  const _Host({required this.initial, required this.onResult});

  final Map<String, Object?>? initial;
  final void Function(Map<String, Object?>?) onResult;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final result = await Navigator.of(context).push<Map<String, Object?>>(
        MaterialPageRoute(
          builder: (_) => NodeFormPage(initial: widget.initial),
        ),
      );
      widget.onResult(result);
    });
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: Text('host')));
}

void main() {
  testWidgets('保存时把键排成 name/type/server/port/uuid 的可读顺序', (tester) async {
    Map<String, Object?>? captured;
    await tester.pumpWidget(MaterialApp(
      home: _Host(
        initial: const <String, Object?>{
          // 故意用乱序 + 表单会补 default 的字段
          'uuid': 'b831381d-6324-4d53-ad4f-8cda48b30811',
          'port': 443,
          'server': '198.51.100.7',
          'type': 'vless',
          'name': 'n1',
        },
        onResult: (r) => captured = r,
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.text('保存'));
    await tester.pumpAndSettle();

    expect(captured, isNotNull);
    expect(captured!.keys.toList(), <String>[
      'name',
      'type',
      'server',
      'port',
      'uuid',
    ]);
    expect(captured!['type'], 'vless');
    expect(captured!['name'], 'n1');
  });
}
