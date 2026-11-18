import 'package:clashdeck/ui/chips.dart';
import 'package:clashdeck/ui/theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG 对比度：浅色主题下选中胶囊必须一眼能看清（用户吐槽过白底发虚）。
double _ratio(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  final hi = la > lb ? la : lb;
  final lo = la > lb ? lb : la;
  return (hi + 0.05) / (lo + 0.05);
}

void main() {
  test('浅色主题选中胶囊的前景与底色对比度 ≥ 4.5', () {
    final scheme = ClashDeckTheme.light().colorScheme;
    final accent = chipSelectionColor(scheme);
    final bg = Color.alphaBlend(
      accent.withValues(alpha: 0.16),
      scheme.surfaceContainerHigh,
    );
    expect(_ratio(accent, bg), greaterThanOrEqualTo(4.5));
  });

  test('深色主题选中胶囊仍是品牌紫', () {
    final scheme = ClashDeckTheme.dark().colorScheme;
    expect(chipSelectionColor(scheme), scheme.primary);
  });

  testWidgets('NameChip 选中只靠紫底紫边，无对勾，文字用加深色', (tester) async {
    final scheme = ClashDeckTheme.light().colorScheme;
    final accent = chipSelectionColor(scheme);
    await tester.pumpWidget(
      MaterialApp(
        theme: ClashDeckTheme.light(),
        home: const Scaffold(
          body: Center(child: NameChip(name: '香港 01', selected: true)),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check), findsNothing);
    final text = tester.widget<Text>(find.text('香港 01'));
    expect(text.style?.color, accent);

    final container = tester.widget<AnimatedContainer>(
      find.descendant(
        of: find.byType(NameChip),
        matching: find.byType(AnimatedContainer),
      ),
    );
    final border = (container.decoration! as BoxDecoration).border! as Border;
    expect(border.top.color, accent);

    final bg = Color.alphaBlend(
      accent.withValues(alpha: 0.16),
      scheme.surfaceContainerHigh,
    );
    expect(_ratio(text.style!.color!, bg), greaterThanOrEqualTo(4.5));
  });
}
