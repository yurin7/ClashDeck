import 'package:clashdeck/ui/pulse_auto_delay.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('同一配置空延迟数据：第一次触发，之后不再触发', () {
    final gate = PulseAutoDelayGate();
    expect(
      gate.shouldTrigger(
        profile: 'demo.yaml',
        delays: const {},
        measuring: false,
      ),
      isTrue,
    );
    expect(
      gate.shouldTrigger(
        profile: 'demo.yaml',
        delays: const {},
        measuring: false,
      ),
      isFalse,
    );
    expect(gate.done, isTrue);
  });

  test('有延迟数据：不触发', () {
    final gate = PulseAutoDelayGate();
    expect(
      gate.shouldTrigger(
        profile: 'demo.yaml',
        delays: const {'HK-01': 120},
        measuring: false,
      ),
      isFalse,
    );
    expect(
      gate.shouldTrigger(
        profile: 'demo.yaml',
        delays: const {},
        measuring: false,
      ),
      isFalse,
    );
  });

  test('正在测速：不并发触发，且不再补触发', () {
    final gate = PulseAutoDelayGate();
    expect(
      gate.shouldTrigger(
        profile: 'demo.yaml',
        delays: const {},
        measuring: true,
      ),
      isFalse,
    );
    expect(
      gate.shouldTrigger(
        profile: 'demo.yaml',
        delays: const {},
        measuring: false,
      ),
      isFalse,
    );
  });

  test('全部为 null 视作没有数据', () {
    final gate = PulseAutoDelayGate();
    expect(
      gate.shouldTrigger(
        profile: 'demo.yaml',
        delays: const {'HK-01': null},
        measuring: false,
      ),
      isTrue,
    );
  });

  test('切换配置后，新配置可再自动补测一轮', () {
    final gate = PulseAutoDelayGate();
    expect(
      gate.shouldTrigger(profile: 'a.yaml', delays: const {}, measuring: false),
      isTrue,
    );
    expect(
      gate.shouldTrigger(profile: 'a.yaml', delays: const {}, measuring: false),
      isFalse,
    );
    expect(
      gate.shouldTrigger(profile: 'b.yaml', delays: const {}, measuring: false),
      isTrue,
    );
    expect(
      gate.shouldTrigger(profile: 'b.yaml', delays: const {}, measuring: false),
      isFalse,
    );
    // 切回 a：本次会话已测过 a，不再触发。
    expect(
      gate.shouldTrigger(profile: 'a.yaml', delays: const {}, measuring: false),
      isFalse,
    );
  });
}
