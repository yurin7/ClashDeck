import 'dart:math' as math;

import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

import 'fields.dart';
import 'motion.dart';
import 'theme.dart';
import 'widgets.dart';
import 'widgets/app_ink.dart';

class DesktopCommand {
  const DesktopCommand({
    required this.icon,
    required this.label,
    required this.run,
    this.hint,
    this.keywords = '',
  });

  final IconData icon;
  final String label;
  final VoidCallback run;
  final String? hint;
  final String keywords;
}

Future<DesktopCommand?> showDesktopCommands(
  BuildContext context,
  List<DesktopCommand> commands,
) {
  final motion = Motion.of(context);
  return showAppDialog<DesktopCommand>(
    context,
    width: (MediaQuery.sizeOf(context).width - 48).clamp(0.0, 560.0),
    transitionDuration: motion.reduceMotion ? Duration.zero : motion.expand,
    builder: (_) => _CommandPalette(commands: commands),
  );
}

class DesktopCommandLauncher extends StatelessWidget {
  const DesktopCommandLauncher({super.key, this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final radius = BorderRadius.circular(Radiuses.sm);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.surfaceContainerHigh.withValues(alpha: 0.5),
        border: Border.all(color: colors.outlineVariant),
        borderRadius: radius,
      ),
      child: AppInkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: Insets.sm + 2,
            vertical: Insets.md,
          ),
          child: Row(
            children: [
              Icon(Icons.bolt_outlined, size: 17, color: colors.primary),
              const SizedBox(width: Insets.xs),
              Expanded(
                child: Text(
                  '快速操作',
                  style: Theme.of(context).textTheme.labelMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text('Ctrl+K', style: mono(9, color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

class _CommandPalette extends StatefulWidget {
  const _CommandPalette({required this.commands});

  final List<DesktopCommand> commands;

  @override
  State<_CommandPalette> createState() => _CommandPaletteState();
}

class _CommandPaletteState extends State<_CommandPalette> {
  static const _itemHeight = 50.0;
  final _search = TextEditingController();
  final _scroll = ScrollController();
  late var _matches = widget.commands;
  var _selected = 0;

  @override
  void dispose() {
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _filter(String value) {
    final words = value.trim().toLowerCase().split(RegExp(r'\s+'));
    setState(() {
      _selected = 0;
      _matches = widget.commands
          .where((command) {
            final text =
                '${command.label} ${command.hint ?? ''} ${command.keywords}'
                    .toLowerCase();
            return words.every(text.contains);
          })
          .toList(growable: false);
    });
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  void _execute(DesktopCommand command) => Navigator.pop(context, command);

  KeyEventResult _handleKey(FocusNode node, KeyEvent event) {
    final composing = _search.value.composing;
    if ((event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        (composing.isValid && !composing.isCollapsed) ||
        _matches.isEmpty) {
      return KeyEventResult.ignored;
    }
    final delta = switch (event.logicalKey) {
      LogicalKeyboardKey.arrowDown => 1,
      LogicalKeyboardKey.arrowUp => -1,
      _ => 0,
    };
    if (delta == 0) return KeyEventResult.ignored;
    final next = (_selected + delta).clamp(0, _matches.length - 1);
    if (next == _selected) return KeyEventResult.handled;
    setState(() => _selected = next);
    if (_scroll.hasClients) {
      final position = _scroll.position;
      final start = Insets.sm + next * _itemHeight;
      final target = position.pixels
          .clamp(start + _itemHeight - position.viewportDimension, start)
          .clamp(0.0, position.maxScrollExtent);
      if (target != position.pixels) _scroll.jumpTo(target);
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final height = (MediaQuery.sizeOf(context).height - 136).clamp(80.0, 350.0);
    return Focus(
      onKeyEvent: _handleKey,
      child: Material(
        color: colors.surfaceContainerHigh,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radiuses.lg),
          side: BorderSide(color: colors.outlineVariant),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.all(Insets.lg),
              child: AppTextField(
                controller: _search,
                autofocus: true,
                hint: '搜索操作或配置',
                prefixIcon: const Icon(Icons.search, size: 19),
                onChanged: _filter,
                onSubmitted: (_) {
                  if (_matches.isNotEmpty) _execute(_matches[_selected]);
                },
              ),
            ),
            const Hairline(),
            if (_matches.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Insets.xl),
                child: Text('没有匹配的操作', style: hintStyle(context)),
              )
            else
              SizedBox(
                height: math.min(height, _matches.length * _itemHeight + 16),
                child: ListView.builder(
                  controller: _scroll,
                  padding: const EdgeInsets.all(Insets.sm),
                  itemExtent: _itemHeight,
                  itemCount: _matches.length,
                  itemBuilder: (context, index) {
                    final command = _matches[index];
                    final selected = index == _selected;
                    final radius = BorderRadius.circular(Radiuses.sm);
                    return Semantics(
                      selected: selected,
                      child: AppInkWell(
                        borderRadius: radius,
                        onTap: () => _execute(command),
                        child: AnimatedContainer(
                          duration: Motion.of(context).fast,
                          decoration: BoxDecoration(
                            color: selected
                                ? colors.primary.withValues(alpha: 0.14)
                                : Colors.transparent,
                            borderRadius: radius,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: Insets.md,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                command.icon,
                                size: 19,
                                color: selected
                                    ? colors.primary
                                    : colors.onSurfaceVariant,
                              ),
                              const SizedBox(width: Insets.md),
                              Expanded(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      command.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: display(14, weight: 550),
                                    ),
                                    if (command.hint case final hint?)
                                      Text(
                                        hint,
                                        style: hintStyle(context),
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                  ],
                                ),
                              ),
                              if (selected)
                                Icon(
                                  Icons.keyboard_return,
                                  color: colors.primary,
                                  size: 15,
                                ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ),
            const Hairline(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Insets.lg,
                Insets.sm,
                Insets.lg,
                Insets.md,
              ),
              child: Text(
                '↑ ↓ 选择   ·   Enter 执行   ·   Esc 关闭',
                style: hintStyle(context),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
