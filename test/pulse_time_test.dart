import 'package:clashdeck/ui/pulse_time.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('时间戳使用 24 小时制并补零', () {
    expect(pulseSpeedStamp(DateTime(2026, 11, 19, 1, 13)), '11-19 01:13');
    expect(pulseSpeedStamp(DateTime(2026, 11, 19, 13, 5)), '11-19 13:05');
    expect(pulseSpeedStamp(DateTime(2026, 1, 2, 0, 0)), '01-02 00:00');
    expect(pulseSpeedStamp(DateTime(2026, 11, 9, 23, 59)), '11-09 23:59');
  });
}
