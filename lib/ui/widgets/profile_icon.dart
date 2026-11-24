import 'package:material_ui/material_ui.dart';

import '../../data/profile_store.dart';
import '../motion.dart';
import '../theme.dart';

class ProfileIcon extends StatelessWidget {
  const ProfileIcon({
    super.key,
    required this.origin,
    this.selected = false,
    this.running = false,
    this.switching = false,
    this.size = 36,
  });

  final ProfileOrigin origin;
  final bool selected;
  final bool running;
  final bool switching;
  final double size;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final motion = Motion.of(context);
    final symbol = switching
        ? Icons.sync
        : running
        ? Icons.play_circle_outline
        : switch (origin) {
            ProfileOrigin.local => Icons.description_outlined,
            ProfileOrigin.imported => Icons.file_download_outlined,
            ProfileOrigin.subscription => Icons.rss_feed,
          };
    final highlight = selected;
    return AnimatedContainer(
      duration: motion.expand,
      curve: motion.enter,
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: highlight
            ? colors.primaryContainer
            : colors.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Radiuses.sm),
        border: Border.all(
          color: highlight ? colors.primary : colors.outlineVariant,
        ),
      ),
      child: AnimatedSwitcher(
        duration: motion.expand,
        child: Icon(
          symbol,
          key: ValueKey(symbol),
          size: size <= 30 ? 16 : 20,
          color: highlight || origin == ProfileOrigin.subscription
              ? colors.primary
              : colors.onSurfaceVariant,
        ),
      ),
    );
  }
}
