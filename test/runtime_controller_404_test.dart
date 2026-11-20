import 'package:clashdeck/core/model/app_settings.dart';
import 'package:clashdeck/core/yaml/yaml_doc.dart';
import 'package:clashdeck/runtime/mihomo_api.dart';
import 'package:clashdeck/runtime/runtime_controller.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// 假 API：不联网，按需返回 proxies 映射、记录 selects、可模拟 404。
class _FakeApi extends MihomoApi {
  _FakeApi({this.members = const {}, this.failSelect = false}) : super(port: 1);

  /// groupName -> member names
  final Map<String, List<String>> members;
  final bool failSelect;

  final List<String> selects = <String>[];
  int pings = 0;

  @override
  Future<bool> ping() async {
    pings++;
    return true;
  }

  @override
  Future<Map<String, Map<String, Object?>>> proxyMap() async => {
    for (final entry in members.entries)
      entry.key: <String, Object?>{
        'all': entry.value,
        'now': entry.value.first,
      },
  };

  @override
  Future<void> selectProxy(String group, String name) async {
    selects.add('$group/$name');
    if (failSelect) throw Exception('404 {"message":"Resource not found"}');
  }

  @override
  void close() {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const sample = '''
mixed-port: 7890
proxies:
  - {name: A, type: ss, server: a.example, port: 443, cipher: aes-128-gcm, password: p}
  - {name: B, type: ss, server: b.example, port: 443, cipher: aes-128-gcm, password: p}
proxy-groups:
  - name: 链式
    type: select
    proxies: [A, B]
rules:
  - MATCH,链式
''';

  RuntimeController build(
    _FakeApi api, {
    Map<String, String> groupNodes = const {},
    String? globalNode,
    void Function(String group, String? node)? pruneSavedExit,
    void Function()? pruneSavedGlobalExit,
  }) => RuntimeController(
    configProvider: () => YamlDoc.parse(sample),
    channel: const MethodChannel('test/runtime404'),
    secret: 'tok',
    androidOverride: true,
    apiOverride: api,
    pollInterval: const Duration(hours: 1),
    settingsProvider: () => AppSettings.defaults.copyWith(
      groupNodes: groupNodes,
      globalNode: globalNode,
    ),
    pruneSavedExit: pruneSavedExit,
    pruneSavedGlobalExit: pruneSavedGlobalExit,
  );

  test('重放时失效的组出口会被跳过并从 sidecar 删除', () async {
    final pruned = <String>[];
    final api = _FakeApi(
      members: {
        '链式': ['A', 'B'],
      },
    );
    final controller = build(
      api,
      groupNodes: {'已删除的组': 'A'},
      pruneSavedExit: (group, node) => pruned.add('$group/$node'),
    );
    await controller.applyStatus({
      'running': true,
      'pid': 42,
      'kernelState': 'running',
    });
    await Future<void>.delayed(Duration.zero);
    expect(pruned, ['已删除的组/null']);
    expect(api.selects, isEmpty);
    expect(controller.phase, RuntimePhase.running);
    expect(controller.lastError, isNull);
  });

  test('节点不在组里也不重放，直接从 sidecar 清掉', () async {
    final pruned = <String>[];
    final api = _FakeApi(
      members: {
        '链式': ['A', 'B'],
      },
    );
    final controller = build(
      api,
      groupNodes: {'链式': '不存在节点'},
      pruneSavedExit: (group, node) => pruned.add('$group/$node'),
    );
    await controller.applyStatus({'running': true, 'pid': 7});
    await Future<void>.delayed(Duration.zero);
    expect(pruned, ['链式/null']);
    expect(api.selects, isEmpty);
    expect(controller.phase, RuntimePhase.running);
  });

  test('重放的 404 不把内核状态标成 error', () async {
    final api = _FakeApi(
      members: {
        '链式': ['A', 'B'],
      },
      failSelect: true,
    );
    final controller = build(api, groupNodes: {'链式': 'B'});
    await controller.applyStatus({'running': true, 'pid': 9});
    await Future<void>.delayed(Duration.zero);
    expect(api.selects, ['链式/B']);
    expect(controller.phase, RuntimePhase.running);
    expect(controller.lastError, isNull);
  });

  test('running 快照会清掉上一次操作留下的错误', () async {
    final api = _FakeApi(
      members: {
        '链式': ['A', 'B'],
      },
    );
    final controller = build(api);
    await controller.applyStatus({
      'error': '切换节点失败：404 {"message":"Resource not found"}',
    });
    expect(controller.phase, RuntimePhase.error);

    await controller.applyStatus({
      'running': true,
      'pid': 11,
      'kernelState': 'running',
    });
    expect(controller.phase, RuntimePhase.running);
    expect(controller.lastError, isNull);
  });

  test('idle 分支在服务还活着时也会启动轮询，并清掉残留 pid', () async {
    final api = _FakeApi(
      members: {
        '链式': ['A'],
      },
    );
    final controller = build(api);
    await controller.applyStatus({'serviceRunning': true, 'pid': 0});
    expect(controller.phase, RuntimePhase.idle);
    expect(controller.polling, isTrue);
    controller.dispose();
  });
}
