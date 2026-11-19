import 'package:material_ui/material_ui.dart';

import '../theme.dart';

/// 延迟文案：`120 ms`；TCP 近似值加前缀 `≈`；无结果统一「超时」。
String formatDelay(int? milliseconds, {bool approx = false}) {
  if (milliseconds == null) return '超时';
  return approx ? '≈$milliseconds ms' : '$milliseconds ms';
}

/// 延迟胶囊：把「未测速 / 123 ms / 超时」按阈值画成小徽章。
///
/// 阈值与 Pulse 的测速行保持一致：< 200 绿、< 500 琥珀、其它红、超时灰。
class DelayBadge extends StatelessWidget {
  const DelayBadge({super.key, required this.text});

  final String text;

  static Color colorOf(String text, ColorScheme scheme) {
    final value = text.trim();
    if (value.isEmpty || value == '—' || value == '未测速') {
      return scheme.outline;
    }
    if (value == '超时' || value == '失败') return scheme.error;
    final ms = int.tryParse(value.replaceAll(RegExp(r'[^0-9]'), ''));
    if (ms == null) return scheme.outline;
    if (ms < 200) return const Color(0xFF3FB950);
    if (ms < 500) return const Color(0xFFD29922);
    return scheme.error;
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = colorOf(text, scheme);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.all(Radiuses.chip),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: mono(10.5, color: color, letterSpacing: 0.2),
        maxLines: 1,
      ),
    );
  }
}
