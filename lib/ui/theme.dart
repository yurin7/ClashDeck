import 'package:material_ui/material_ui.dart';

/// 设计系统：一套「网络仪表盘」气质的令牌 —— 暗色为默认画布、细描边代替投影、
/// 等宽字体承载数据、显示字体承载标题与大号数值。
///
/// 为什么不用 Material 默认视觉：默认的卡片投影 + 种子色让每个页面都长得像
/// 表单应用，而 Clash 客户端真正要突出的是「连接状态、流量、配置差异」这些
/// 数据。这里统一成：近黑画布 + 1px 细线 + 等宽数据 + 一枚主色高亮。

// ---------------------------------------------------------------------------
// 间距与圆角
// ---------------------------------------------------------------------------

abstract final class Insets {
  static const double xs = 4;
  static const double sm = 8;
  static const double md = 12;
  static const double lg = 16;
  static const double xl = 24;
  static const double xxl = 32;
}

abstract final class Radiuses {
  static const double xs = 6;
  static const double sm = 10;
  static const double md = 14;
  static const double lg = 18;
  static const double xl = 24;
  static const Radius chip = Radius.circular(9);
  static const Radius card = Radius.circular(18);
  static const Radius sheet = Radius.circular(24);
}

// ---------------------------------------------------------------------------
// 字体
// ---------------------------------------------------------------------------

const String kDisplayFont = 'SpaceGrotesk';
const String kMonoFont = 'JetBrainsMono';

/// 显示字体（标题 / 大号数值）。变量字体，字重靠 [FontVariation] 指定。
TextStyle display(
  double size, {
  int weight = 700,
  Color? color,
  double? letterSpacing,
  double? height,
}) => TextStyle(
  fontFamily: kDisplayFont,
  fontSize: size,
  color: color,
  letterSpacing: letterSpacing ?? (size >= 24 ? -0.8 : -0.2),
  height: height ?? 1.1,
  fontVariations: [FontVariation('wght', weight.toDouble())],
);

/// 等宽字体（YAML / 规则 / 日志 / 元信息）。
TextStyle mono(
  double size, {
  int weight = 400,
  Color? color,
  double? letterSpacing,
  double? height,
}) => TextStyle(
  fontFamily: kMonoFont,
  fontSize: size,
  color: color,
  letterSpacing: letterSpacing ?? 0,
  height: height ?? 1.35,
  fontVariations: [FontVariation('wght', weight.toDouble())],
);

/// 旧 API：等宽样式（保留给已有页面）。
TextStyle monoStyle(BuildContext context, {double? size, Color? color}) =>
    mono(size ?? 12.5, color: color ?? Theme.of(context).colorScheme.onSurface);

/// 微标签：大写、宽字距，用来做分区标题。
TextStyle microStyle(BuildContext context, {Color? color}) => display(
  10.5,
  weight: 600,
  color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
  letterSpacing: 1.6,
);

/// 次要说明文字。
TextStyle? hintStyle(BuildContext context) =>
    Theme.of(context).textTheme.bodySmall
        ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant);

// ---------------------------------------------------------------------------
// 调色板
// ---------------------------------------------------------------------------

/// 主色：靛蓝 -> 紫的渐变起点。
const Color kBrandSeed = Color(0xFF6E8BFF);
const Color kBrandAccent = Color(0xFF9B7BFF);

const Color _ink = Color(0xFF080A0F);
const Color _inkSurface = Color(0xFF0E1118);
const Color _inkSurfaceHi = Color(0xFF141925);
const Color _inkHairline = Color(0xFF1E2530);
const Color _inkText = Color(0xFFF2F5FB);
const Color _inkDim = Color(0xFF8E99AD);
const Color _mint = Color(0xFF2EE6A8);
const Color _amber = Color(0xFFF2C14E);
const Color _rose = Color(0xFFFF6E6E);

const Color _paper = Color(0xFFF6F7FB);
const Color _paperSurface = Color(0xFFFFFFFF);
const Color _paperSurfaceHi = Color(0xFFEFF1F7);
const Color _paperHairline = Color(0xFFE3E7EF);
const Color _paperText = Color(0xFF0B0E14);
const Color _paperDim = Color(0xFF5D6779);

/// 语义色（成功/警告/危险），跟随明暗主题。
class SemanticColors extends ThemeExtension<SemanticColors> {
  const SemanticColors({
    required this.ok,
    required this.warn,
    required this.danger,
    required this.accentGradient,
  });

  final Color ok;
  final Color warn;
  final Color danger;
  final List<Color> accentGradient;

  static const dark = SemanticColors(
    ok: _mint,
    warn: _amber,
    danger: _rose,
    accentGradient: [kBrandSeed, kBrandAccent],
  );

  static const light = SemanticColors(
    ok: Color(0xFF0FA97B),
    warn: Color(0xFFE08A00),
    danger: Color(0xFFDC4B4B),
    accentGradient: [Color(0xFF4B5FE0), Color(0xFF7B5BE0)],
  );

  @override
  SemanticColors copyWith({
    Color? ok,
    Color? warn,
    Color? danger,
    List<Color>? accentGradient,
  }) => SemanticColors(
    ok: ok ?? this.ok,
    warn: warn ?? this.warn,
    danger: danger ?? this.danger,
    accentGradient: accentGradient ?? this.accentGradient,
  );

  @override
  SemanticColors lerp(ThemeExtension<SemanticColors>? other, double t) {
    if (other is! SemanticColors) return this;
    return SemanticColors(
      ok: Color.lerp(ok, other.ok, t)!,
      warn: Color.lerp(warn, other.warn, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      accentGradient: [
        for (var i = 0; i < accentGradient.length; i++)
          Color.lerp(accentGradient[i], other.accentGradient[i], t)!,
      ],
    );
  }
}

extension SemanticColorsX on BuildContext {
  SemanticColors get semantic =>
      Theme.of(this).extension<SemanticColors>() ?? SemanticColors.dark;
}

// ---------------------------------------------------------------------------
// 主题
// ---------------------------------------------------------------------------

ThemeData buildTheme(Brightness brightness) {
  final dark = brightness == Brightness.dark;
  final canvas = dark ? _ink : _paper;
  final surface = dark ? _inkSurface : _paperSurface;
  final surfaceHi = dark ? _inkSurfaceHi : _paperSurfaceHi;
  final hairline = dark ? _inkHairline : _paperHairline;
  final text = dark ? _inkText : _paperText;
  final dim = dark ? _inkDim : _paperDim;
  final semantic = dark ? SemanticColors.dark : SemanticColors.light;

  final scheme = ColorScheme(
    brightness: brightness,
    primary: kBrandSeed,
    onPrimary: Colors.white,
    primaryContainer: dark ? const Color(0xFF1B2340) : const Color(0xFFE2E7FF),
    onPrimaryContainer: dark ? kBrandSeed : const Color(0xFF23308A),
    secondary: kBrandAccent,
    onSecondary: Colors.white,
    secondaryContainer: dark
        ? const Color(0xFF241F3A)
        : const Color(0xFFEDE7FF),
    onSecondaryContainer: dark ? kBrandAccent : const Color(0xFF3A2C7A),
    tertiary: semantic.ok,
    onTertiary: dark ? _ink : Colors.white,
    tertiaryContainer: dark ? const Color(0xFF10322A) : const Color(0xFFDDF6EC),
    onTertiaryContainer: semantic.ok,
    error: semantic.danger,
    onError: dark ? _ink : Colors.white,
    errorContainer: dark ? const Color(0xFF3A1A1C) : const Color(0xFFFCE4E4),
    onErrorContainer: semantic.danger,
    surface: surface,
    onSurface: text,
    surfaceContainerLowest: dark ? canvas : Colors.white,
    surfaceContainerLow: surface,
    surfaceContainer: surfaceHi,
    surfaceContainerHigh: dark
        ? const Color(0xFF1A2130)
        : const Color(0xFFE9ECF4),
    surfaceContainerHighest: dark
        ? const Color(0xFF222A3A)
        : const Color(0xFFE1E5EF),
    onSurfaceVariant: dim,
    outline: dark ? const Color(0xFF39424F) : const Color(0xFFC9D0DC),
    outlineVariant: hairline,
    inverseSurface: text,
    onInverseSurface: surface,
  );

  final base = ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: canvas,
    splashFactory: InkSparkle.splashFactory,
    visualDensity: VisualDensity.standard,
  );

  final textTheme = base.textTheme.copyWith(
    displayLarge: display(44, weight: 700, color: text),
    displayMedium: display(34, weight: 700, color: text),
    displaySmall: display(28, weight: 700, color: text),
    headlineMedium: display(24, weight: 700, color: text),
    headlineSmall: display(20, weight: 700, color: text),
    titleLarge: display(18, weight: 600, color: text),
    titleMedium: display(15.5, weight: 600, color: text, letterSpacing: -0.1),
    titleSmall: display(13.5, weight: 600, color: text, letterSpacing: 0),
    bodyLarge: TextStyle(fontSize: 15, color: text, height: 1.45),
    bodyMedium: TextStyle(fontSize: 13.5, color: text, height: 1.45),
    bodySmall: TextStyle(fontSize: 12, color: dim, height: 1.4),
    labelLarge: display(13.5, weight: 600, color: text, letterSpacing: 0.2),
    labelMedium: display(12, weight: 600, color: dim, letterSpacing: 0.4),
    labelSmall: display(10.5, weight: 600, color: dim, letterSpacing: 1.4),
  );

  return base.copyWith(
    textTheme: textTheme,
    extensions: [semantic],
    appBarTheme: AppBarTheme(
      backgroundColor: canvas,
      surfaceTintColor: Colors.transparent,
      foregroundColor: text,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleSpacing: Insets.xs,
      titleTextStyle: display(19, weight: 600, color: text),
      actionsIconTheme: IconThemeData(color: dim, size: 20),
      iconTheme: IconThemeData(color: text, size: 20),
    ),
    cardTheme: CardThemeData(
      color: surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.lg),
        side: BorderSide(color: hairline, width: 1),
      ),
    ),
    dividerTheme: DividerThemeData(color: hairline, thickness: 1, space: 1),
    chipTheme: ChipThemeData(
      backgroundColor: Colors.transparent,
      selectedColor: scheme.primaryContainer,
      side: BorderSide(color: hairline),
      labelStyle: display(12, weight: 600, color: text),
      secondaryLabelStyle: display(12, weight: 600, color: dim),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.sm),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      showCheckmark: false,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: surfaceHi,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: Insets.md,
        vertical: Insets.md,
      ),
      hintStyle: TextStyle(fontSize: 13.5, color: dim.withValues(alpha: 0.75)),
      helperStyle: TextStyle(fontSize: 11.5, color: dim),
      labelStyle: TextStyle(fontSize: 13, color: dim),
      floatingLabelStyle: display(12.5, weight: 600, color: scheme.primary),
      prefixIconColor: dim,
      suffixIconColor: dim,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radiuses.md),
        borderSide: BorderSide(color: hairline),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radiuses.md),
        borderSide: BorderSide(color: hairline),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radiuses.md),
        borderSide: BorderSide(color: scheme.primary, width: 1.4),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radiuses.md),
        borderSide: BorderSide(color: semantic.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Radiuses.md),
        borderSide: BorderSide(color: semantic.danger, width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: scheme.primary,
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 44),
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        textStyle: display(
          14,
          weight: 600,
          color: Colors.white,
          letterSpacing: 0.2,
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radiuses.md),
        ),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: text,
        minimumSize: const Size(0, 44),
        side: BorderSide(color: hairline),
        padding: const EdgeInsets.symmetric(horizontal: Insets.lg),
        textStyle: display(14, weight: 600, color: text, letterSpacing: 0.2),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radiuses.md),
        ),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: scheme.primary,
        textStyle: display(13.5, weight: 600, color: scheme.primary),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Radiuses.sm),
        ),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: dim,
        highlightColor: scheme.primary.withValues(alpha: 0.08),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected) ? Colors.white : dim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? scheme.primary : surfaceHi,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (states) =>
            states.contains(WidgetState.selected) ? scheme.primary : hairline,
      ),
    ),
    sliderTheme: SliderThemeData(
      activeTrackColor: scheme.primary,
      inactiveTrackColor: surfaceHi,
      thumbColor: scheme.primary,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: text,
      unselectedLabelColor: dim,
      indicatorColor: scheme.primary,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: Colors.transparent,
      labelStyle: display(13.5, weight: 700, color: text, letterSpacing: 0.2),
      unselectedLabelStyle: display(
        13.5,
        weight: 500,
        color: dim,
        letterSpacing: 0.2,
      ),
      overlayColor: WidgetStatePropertyAll(
        scheme.primary.withValues(alpha: 0.06),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: dark ? _inkSurfaceHi : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.xl),
        side: BorderSide(color: hairline),
      ),
      titleTextStyle: display(18, weight: 700, color: text),
      contentTextStyle: TextStyle(fontSize: 13.5, color: text, height: 1.5),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: dark ? _inkSurfaceHi : Colors.white,
      surfaceTintColor: Colors.transparent,
      modalBackgroundColor: dark ? _inkSurfaceHi : Colors.white,
      modalBarrierColor: Colors.black.withValues(alpha: dark ? 0.6 : 0.35),
      showDragHandle: true,
      dragHandleColor: hairline,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(Radiuses.xl)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: dark ? _inkSurfaceHi : Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.md),
        side: BorderSide(color: hairline),
      ),
      textStyle: TextStyle(fontSize: 13.5, color: text),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? const Color(0xFF232A3A) : const Color(0xFF1B2130),
      contentTextStyle: TextStyle(fontSize: 13, color: _inkText),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Radiuses.md),
      ),
      insetPadding: const EdgeInsets.all(Insets.lg),
      actionTextColor: kBrandSeed,
    ),
    listTileTheme: ListTileThemeData(
      iconColor: dim,
      textColor: text,
      subtitleTextStyle: TextStyle(fontSize: 12, color: dim),
      titleTextStyle: display(14, weight: 600, color: text),
      contentPadding: const EdgeInsets.symmetric(horizontal: Insets.lg),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: scheme.primary,
      linearTrackColor: surfaceHi,
      circularTrackColor: surfaceHi,
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? const Color(0xFF2A3244) : const Color(0xFF1B2130),
        borderRadius: BorderRadius.circular(Radiuses.sm),
      ),
      textStyle: TextStyle(fontSize: 12, color: _inkText),
    ),
    expansionTileTheme: ExpansionTileThemeData(
      iconColor: dim,
      collapsedIconColor: dim,
      textColor: text,
      collapsedTextColor: text,
      childrenPadding: const EdgeInsets.fromLTRB(
        Insets.lg,
        0,
        Insets.lg,
        Insets.md,
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.macOS: FadeForwardsPageTransitionsBuilder(),
      },
    ),
  );
}

abstract final class ClashDeckTheme {
  static ThemeData light() => buildTheme(Brightness.light);
  static ThemeData dark() => buildTheme(Brightness.dark);
}
