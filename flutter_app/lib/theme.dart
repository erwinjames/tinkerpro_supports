import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

class Brand {
  Brand._();

  static const Color _darkCanvas = navy;
  static const Color _darkSurface = Color(0xFF12304F);
  static const Color _darkSurfaceHi = Color(0xFF1B3D62);
  static const Color _darkPaper = Color(0xFFEAF0F7);
  static const Color _darkPaperDim = Color(0xFF9DB0C6);
  static const Color _darkRule = Color(0xFF23456B);
  static const Color orange = Color(0xFFFF7D00);
  static const Color navy = Color(0xFF0C233E);
  static const Color white = Color(0xFFFFFFFF);
  static const Color _signal = orange;

  static const Color _lightCanvas = Color(0xFFF4F7FB);
  static const Color _lightSurface = white;
  static const Color _lightSurfaceHi = Color(0xFFE8EEF6);
  static const Color _lightPaper = navy;
  static const Color _lightPaperDim = Color(0xFF54677F);
  static const Color _lightRule = Color(0xFFD3DDEA);

  static const Color canvas = _darkCanvas;
  static const Color surface = _darkSurface;
  static const Color surfaceHi = _darkSurfaceHi;
  static const Color paper = _darkPaper;
  static const Color paperDim = _darkPaperDim;
  static const Color rule = _darkRule;
  static const Color signal = _signal;
  static const Color onSignal = white;

  static const Color success = Color(0xFF16A34A);
  static const Color warning = Color(0xFFF59E0B);
  static const Color danger = Color(0xFFE5484D);
  static const Color info = Color(0xFF3B82F6);
  static const Color pageVoice = Color(0xFF12A55F);

  static const double radiusSm = 8;
  static const double radius = 12;
  static const double radiusLg = 16;

  static Color signalGlow([double alpha = 0.12]) =>
      _signal.withValues(alpha: alpha);

  static BrandColors forBrightness(Brightness b) {
    return b == Brightness.dark
        ? const BrandColors(
            canvas: _darkCanvas,
            surface: _darkSurface,
            surfaceHi: _darkSurfaceHi,
            paper: _darkPaper,
            paperDim: _darkPaperDim,
            rule: _darkRule,
            signal: _signal,
          )
        : const BrandColors(
            canvas: _lightCanvas,
            surface: _lightSurface,
            surfaceHi: _lightSurfaceHi,
            paper: _lightPaper,
            paperDim: _lightPaperDim,
            rule: _lightRule,
            signal: _signal,
          );
  }
}

@immutable
class BrandColors extends ThemeExtension<BrandColors> {
  const BrandColors({
    required this.canvas,
    required this.surface,
    required this.surfaceHi,
    required this.paper,
    required this.paperDim,
    required this.rule,
    required this.signal,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceHi;
  final Color paper;
  final Color paperDim;
  final Color rule;
  final Color signal;

  Color get onSignal => Brand.onSignal;
  Color get success => Brand.success;
  Color get warning => Brand.warning;
  Color get danger => Brand.danger;
  Color get info => Brand.info;

  bool get isDark => canvas.computeLuminance() < 0.2;

  Color get signalInk =>
      isDark ? const Color(0xFFFF9A3D) : const Color(0xFFC25E00);

  Color signalGlow([double alpha = 0.12]) => signal.withValues(alpha: alpha);

  Color tint(Color color, [double alpha = 0.12]) =>
      color.withValues(alpha: isDark ? alpha + 0.06 : alpha);

  List<BoxShadow> get shadow => isDark
      ? const []
      : [
          BoxShadow(
            color: Brand.navy.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, 2),
          ),
        ];

  @override
  BrandColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceHi,
    Color? paper,
    Color? paperDim,
    Color? rule,
    Color? signal,
  }) {
    return BrandColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceHi: surfaceHi ?? this.surfaceHi,
      paper: paper ?? this.paper,
      paperDim: paperDim ?? this.paperDim,
      rule: rule ?? this.rule,
      signal: signal ?? this.signal,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      canvas: Color.lerp(canvas, other.canvas, t) ?? canvas,
      surface: Color.lerp(surface, other.surface, t) ?? surface,
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t) ?? surfaceHi,
      paper: Color.lerp(paper, other.paper, t) ?? paper,
      paperDim: Color.lerp(paperDim, other.paperDim, t) ?? paperDim,
      rule: Color.lerp(rule, other.rule, t) ?? rule,
      signal: Color.lerp(signal, other.signal, t) ?? signal,
    );
  }
}

extension BrandContext on BuildContext {
  BrandColors get brand => Theme.of(this).extension<BrandColors>()!;
}

TextTheme _buildTextTheme(BrandColors c) {
  final head = GoogleFonts.montserratTextTheme();
  final base = GoogleFonts.interTextTheme();
  TextStyle? s(
    TextStyle? t,
    double size,
    FontWeight w,
    Color color, {
    double? height,
    double spacing = 0,
  }) => t?.copyWith(
    fontSize: size,
    fontWeight: w,
    color: color,
    height: height,
    letterSpacing: spacing,
  );

  return TextTheme(
    displayLarge: s(
      head.displayLarge,
      40,
      FontWeight.w800,
      c.paper,
      height: 1.1,
      spacing: -1,
    ),
    displayMedium: s(
      head.displayMedium,
      32,
      FontWeight.w800,
      c.paper,
      height: 1.15,
      spacing: -0.8,
    ),
    displaySmall: s(
      head.displaySmall,
      28,
      FontWeight.w700,
      c.paper,
      height: 1.2,
      spacing: -0.5,
    ),
    headlineLarge: s(
      head.headlineLarge,
      24,
      FontWeight.w700,
      c.paper,
      height: 1.25,
      spacing: -0.4,
    ),
    headlineMedium: s(
      head.headlineMedium,
      20,
      FontWeight.w700,
      c.paper,
      height: 1.3,
      spacing: -0.2,
    ),
    headlineSmall: s(
      head.headlineSmall,
      18,
      FontWeight.w700,
      c.paper,
      height: 1.3,
    ),
    titleLarge: s(head.titleLarge, 17, FontWeight.w700, c.paper, height: 1.3),
    titleMedium: s(
      head.titleMedium,
      15.5,
      FontWeight.w600,
      c.paper,
      height: 1.35,
    ),
    titleSmall: s(base.titleSmall, 15, FontWeight.w600, c.paper, height: 1.35),
    bodyLarge: s(base.bodyLarge, 16, FontWeight.w400, c.paper, height: 1.55),
    bodyMedium: s(base.bodyMedium, 15, FontWeight.w400, c.paper, height: 1.5),
    bodySmall: s(base.bodySmall, 13, FontWeight.w400, c.paperDim, height: 1.45),
    labelLarge: s(
      base.labelLarge,
      14,
      FontWeight.w600,
      c.paper,
      height: 1.3,
      spacing: 0.1,
    ),
    labelMedium: s(
      base.labelMedium,
      12,
      FontWeight.w500,
      c.paperDim,
      height: 1.3,
      spacing: 0.2,
    ),
    labelSmall: s(
      base.labelSmall,
      11,
      FontWeight.w600,
      c.paperDim,
      height: 1.3,
      spacing: 0.3,
    ),
  );
}

ThemeData _build(Brightness brightness) {
  final c = Brand.forBrightness(brightness);
  final text = _buildTextTheme(c);
  final dark = brightness == Brightness.dark;
  final radius = BorderRadius.circular(Brand.radius);
  final smallRadius = BorderRadius.circular(Brand.radiusSm + 2);
  OutlineInputBorder inputBorder(Color color, [double width = 1]) =>
      OutlineInputBorder(
        borderRadius: smallRadius,
        borderSide: BorderSide(color: color, width: width),
      );

  final scheme = (dark ? const ColorScheme.dark() : const ColorScheme.light())
      .copyWith(
        primary: c.signal,
        onPrimary: Brand.onSignal,
        primaryContainer: c.signalGlow(dark ? 0.22 : 0.12),
        onPrimaryContainer: c.signal,
        secondary: c.paper,
        onSecondary: c.surface,
        surface: c.surface,
        onSurface: c.paper,
        onSurfaceVariant: c.paperDim,
        surfaceContainerLowest: c.canvas,
        surfaceContainerLow: c.surface,
        surfaceContainer: c.surface,
        surfaceContainerHigh: c.surfaceHi,
        surfaceContainerHighest: c.surfaceHi,
        outline: c.rule,
        outlineVariant: c.rule,
        error: Brand.danger,
        onError: Colors.white,
      );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    extensions: [c],
    textTheme: text,
    fontFamily: GoogleFonts.inter().fontFamily,
    visualDensity: VisualDensity.standard,
    materialTapTargetSize: MaterialTapTargetSize.padded,
    focusColor: c.signalGlow(0.22),
    iconTheme: IconThemeData(color: c.paper, size: 20),
    primaryIconTheme: const IconThemeData(color: Brand.onSignal, size: 20),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.canvas,
      foregroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.titleLarge,
      iconTheme: IconThemeData(color: c.paper, size: 22),
      systemOverlayStyle: dark
          ? SystemUiOverlayStyle.light
          : SystemUiOverlayStyle.dark,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: radius,
        side: BorderSide(color: c.rule),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.paperDim,
      textColor: c.paper,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      shape: RoundedRectangleBorder(borderRadius: smallRadius),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surfaceHi,
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: inputBorder(c.rule),
      enabledBorder: inputBorder(c.rule),
      disabledBorder: inputBorder(c.rule.withValues(alpha: 0.6)),
      focusedBorder: inputBorder(c.signal, 1.6),
      errorBorder: inputBorder(Brand.danger),
      focusedErrorBorder: inputBorder(Brand.danger, 1.6),
      labelStyle: text.bodyMedium?.copyWith(color: c.paperDim),
      floatingLabelStyle: text.labelLarge?.copyWith(color: c.signal),
      hintStyle: text.bodyMedium?.copyWith(color: c.paperDim),
      helperStyle: text.bodySmall,
      errorStyle: text.bodySmall?.copyWith(color: Brand.danger),
      prefixIconColor: c.paperDim,
      suffixIconColor: c.paperDim,
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.signal,
        foregroundColor: Brand.onSignal,
        disabledBackgroundColor: c.surfaceHi,
        disabledForegroundColor: c.paperDim,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: smallRadius),
        elevation: 0,
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.signal,
        foregroundColor: Brand.onSignal,
        disabledBackgroundColor: c.surfaceHi,
        disabledForegroundColor: c.paperDim,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: smallRadius),
        elevation: 0,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.paper,
        backgroundColor: c.surface,
        minimumSize: const Size(64, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide(color: c.rule),
        textStyle: text.labelLarge?.copyWith(fontSize: 14),
        shape: RoundedRectangleBorder(borderRadius: smallRadius),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.signal,
        textStyle: text.labelLarge,
        shape: RoundedRectangleBorder(borderRadius: smallRadius),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.paper,
        minimumSize: const Size(44, 44),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.signal,
      foregroundColor: Brand.onSignal,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 3,
      highlightElevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      extendedTextStyle: text.labelLarge?.copyWith(fontSize: 14),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surface,
      selectedColor: c.signalGlow(dark ? 0.22 : 0.12),
      disabledColor: c.surfaceHi,
      side: BorderSide(color: c.rule),
      labelStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w500),
      secondaryLabelStyle: text.labelLarge?.copyWith(color: c.signal),
      checkmarkColor: c.signal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.signal : Colors.transparent,
      ),
      checkColor: const WidgetStatePropertyAll(Brand.onSignal),
      side: BorderSide(color: c.paperDim, width: 1.4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(5)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.signal : c.paperDim,
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Colors.white : c.paperDim,
      ),
      trackColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.signal : c.surfaceHi,
      ),
      trackOutlineColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? c.signal : c.rule,
      ),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.signal,
      linearTrackColor: c.surfaceHi,
      circularTrackColor: Colors.transparent,
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.signal,
      unselectedLabelColor: c.paperDim,
      labelStyle: text.labelLarge,
      unselectedLabelStyle: text.labelLarge?.copyWith(
        fontWeight: FontWeight.w500,
      ),
      indicatorColor: c.signal,
      indicatorSize: TabBarIndicatorSize.label,
      dividerColor: c.rule,
    ),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      indicatorColor: c.signalGlow(dark ? 0.22 : 0.12),
      elevation: 0,
      height: 68,
      labelTextStyle: WidgetStateProperty.resolveWith(
        (s) => text.labelMedium?.copyWith(
          color: s.contains(WidgetState.selected) ? c.signal : c.paperDim,
          fontWeight: s.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
        ),
      ),
      iconTheme: WidgetStateProperty.resolveWith(
        (s) => IconThemeData(
          size: 22,
          color: s.contains(WidgetState.selected) ? c.signal : c.paperDim,
        ),
      ),
    ),
    bottomNavigationBarTheme: BottomNavigationBarThemeData(
      backgroundColor: c.surface,
      selectedItemColor: c.signal,
      unselectedItemColor: c.paperDim,
      selectedLabelStyle: text.labelMedium?.copyWith(
        fontWeight: FontWeight.w600,
      ),
      unselectedLabelStyle: text.labelMedium,
      type: BottomNavigationBarType.fixed,
      elevation: 0,
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
      ),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      modalBackgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      showDragHandle: true,
      dragHandleColor: c.rule,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: smallRadius,
        side: BorderSide(color: c.rule),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
        shape: WidgetStatePropertyAll(
          RoundedRectangleBorder(
            borderRadius: smallRadius,
            side: BorderSide(color: c.rule),
          ),
        ),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      textStyle: text.bodyMedium,
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? c.surfaceHi : Brand.navy,
      contentTextStyle: text.bodyMedium?.copyWith(color: Colors.white),
      actionTextColor: c.signal,
      behavior: SnackBarBehavior.floating,
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: smallRadius),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: dark ? c.surfaceHi : Brand.navy,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: text.labelMedium?.copyWith(color: Colors.white),
    ),
    badgeTheme: const BadgeThemeData(
      backgroundColor: Brand.danger,
      textColor: Colors.white,
    ),
    splashFactory: InkSparkle.splashFactory,
    highlightColor: Colors.transparent,
    splashColor: c.signalGlow(0.08),
    hoverColor: c.signalGlow(0.04),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
      },
    ),
  );
}

ThemeData darkTheme() => _build(Brightness.dark);
ThemeData lightTheme() => _build(Brightness.light);
ThemeData buildTheme() => darkTheme();

Color customerStatusColor(String status) {
  switch (status) {
    case 'Completed':
      return Brand.success;
    case 'Upload PTU':
      return Brand.warning;
    case 'Continue Registration':
      return Brand.danger;
    default:
      return Brand.info;
  }
}
