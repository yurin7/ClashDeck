/// Pulse 测速结果的时间戳：`MM-DD HH:mm`（24 小时制，取设备本地时间）。
String pulseSpeedStamp(DateTime time) {
  String two(int value) => value.toString().padLeft(2, '0');
  return '${two(time.month)}-${two(time.day)} '
      '${two(time.hour)}:${two(time.minute)}';
}
