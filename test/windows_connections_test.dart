import 'package:clashdeck/runtime/windows_connections.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('连接按策略组、进程、规则筛选，速率按实际采样间隔计算', () {
    final history = WindowsConnectionHistory();
    Map<String, Object?> snapshot(int bytes, {bool closed = false}) => {
      'downloadTotal': bytes,
      'connections': [
        if (!closed)
          {
            'id': 'demo',
            'download': bytes,
            'metadata': {
              'destinationIP': '2001:db8::1',
              'destinationPort': '443',
              'processPath': r'C:\Apps\Example.EXE',
            },
            'chains': ['东京', '默认出口', '外层策略'],
            'rule': 'DomainSuffix',
            'rulePayload': 'example.org',
          },
      ],
    };

    const groups = {'默认出口', '外层策略'};
    history.apply(snapshot(100), at: Duration.zero, groupNames: groups);
    expect(history.open.single.downRate, isNull);
    history.apply(
      snapshot(700),
      at: const Duration(milliseconds: 1500),
      groupNames: groups,
    );
    final entry = history.open.single;
    expect(entry.destination, '[2001:db8::1]:443');
    expect(entry.chains, ['外层策略', '默认出口', '东京']);
    expect(entry.downRate, 400);
    expect(
      entry.matches(
        keyword: '2001:db8',
        group: '默认出口',
        executable: 'example.exe',
        matchedRule: 'DomainSuffix · example.org',
      ),
      isTrue,
    );
    expect(entry.matches(keyword: '', group: '东京'), isFalse);

    history.apply(
      snapshot(700, closed: true),
      at: const Duration(seconds: 2),
      groupNames: groups,
    );
    expect(history.open, isEmpty);
    expect(history.closed.single.downloaded, 700);
  });
}
