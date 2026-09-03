import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class Brand {
  Brand._();

  /// Brand: TinkerPro orange, deep navy, white.
  static const Color brandOrange = Color(0xFFFF7D00);
  static const Color brandNavy   = Color(0xFF0C233E);

  static const Color _lightCanvas     = Color(0xFFF4F7FB);
  static const Color _lightSurface    = Color(0xFFFFFFFF);
  static const Color _lightSurfaceHi  = Color(0xFFE8EEF6);
  static const Color _lightPaper      = brandNavy;
  static const Color _lightPaperDim   = Color(0xFF54677F);
  static const Color _lightRule       = Color(0xFFD3DDEA);
  static const Color _lightSignalInk  = Color(0xFFB0530A);

  static const Color _darkCanvas      = brandNavy;
  static const Color _darkSurface     = Color(0xFF12304F);
  static const Color _darkSurfaceHi   = Color(0xFF1B3D62);
  static const Color _darkPaper       = Color(0xFFEAF0F7);
  static const Color _darkPaperDim    = Color(0xFF9DB0C6);
  static const Color _darkRule        = Color(0xFF23456B);
  static const Color _darkSignalInk   = Color(0xFFFF9A3D);

  static const Color canvas      = _lightCanvas;
  static const Color surface     = _lightSurface;
  static const Color surfaceHi   = _lightSurfaceHi;
  static const Color paper       = _lightPaper;
  static const Color paperDim    = _lightPaperDim;
  static const Color rule        = _lightRule;
  static const Color signal      = brandOrange;

  /// Ink for anything sitting ON the orange. White fails on #FF7D00 at
  /// 2.6:1; the navy clears AA at 6.2:1, so orange fills carry navy.
  static const Color onSignal    = brandNavy;

  /// The Facebook page's own voice in a thread — green, so it reads apart
  /// from the orange brand accent used for your own messages.
  static const Color pageVoice   = Color(0xFF12A55F);

  static const Color success     = Color(0xFF0E7C4A);
  static const Color danger      = Color(0xFFD92D20);

  static const double radiusSm = 8;
  static const double radius   = 10;
  static const double radiusLg = 14;

  static Color signalGlow([double alpha = 0.12]) =>
      signal.withValues(alpha: alpha);

  static BrandColors forBrightness(Brightness b) {
    return b == Brightness.dark
        ? const BrandColors(
            canvas:    _darkCanvas,
            surface:   _darkSurface,
            surfaceHi: _darkSurfaceHi,
            paper:     _darkPaper,
            paperDim:  _darkPaperDim,
            rule:      _darkRule,
            signal:    brandOrange,
            signalInk: _darkSignalInk,
          )
        : const BrandColors(
            canvas:    _lightCanvas,
            surface:   _lightSurface,
            surfaceHi: _lightSurfaceHi,
            paper:     _lightPaper,
            paperDim:  _lightPaperDim,
            rule:      _lightRule,
            signal:    brandOrange,
            signalInk: _lightSignalInk,
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
    required this.signalInk,
  });

  final Color canvas;
  final Color surface;
  final Color surfaceHi;
  final Color paper;
  final Color paperDim;
  final Color rule;
  final Color signal;

  /// The accent as legible text on this theme's ground — the raw brand
  /// orange is too light for body text on white.
  final Color signalInk;

  Color signalGlow([double alpha = 0.12]) => signal.withValues(alpha: alpha);

  @override
  BrandColors copyWith({
    Color? canvas,
    Color? surface,
    Color? surfaceHi,
    Color? paper,
    Color? paperDim,
    Color? rule,
    Color? signal,
    Color? signalInk,
  }) {
    return BrandColors(
      canvas: canvas ?? this.canvas,
      surface: surface ?? this.surface,
      surfaceHi: surfaceHi ?? this.surfaceHi,
      paper: paper ?? this.paper,
      paperDim: paperDim ?? this.paperDim,
      rule: rule ?? this.rule,
      signal: signal ?? this.signal,
      signalInk: signalInk ?? this.signalInk,
    );
  }

  @override
  BrandColors lerp(ThemeExtension<BrandColors>? other, double t) {
    if (other is! BrandColors) return this;
    return BrandColors(
      canvas:    Color.lerp(canvas,    other.canvas,    t) ?? canvas,
      surface:   Color.lerp(surface,   other.surface,   t) ?? surface,
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t) ?? surfaceHi,
      paper:     Color.lerp(paper,     other.paper,     t) ?? paper,
      paperDim:  Color.lerp(paperDim,  other.paperDim,  t) ?? paperDim,
      rule:      Color.lerp(rule,      other.rule,      t) ?? rule,
      signal:    Color.lerp(signal,    other.signal,    t) ?? signal,
      signalInk: Color.lerp(signalInk, other.signalInk, t) ?? signalInk,
    );
  }
}

extension BrandContext on BuildContext {
  BrandColors get brand => Theme.of(this).extension<BrandColors>()!;
}

TextTheme _buildTextTheme(BrandColors c) {
  final base = GoogleFonts.plusJakartaSansTextTheme();

  return TextTheme(
    displayLarge: base.displayLarge?.copyWith(
      fontSize: 40,
      fontWeight: FontWeight.w800,
      height: 1.1,
      letterSpacing: -1,
      color: c.paper,
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.6,
      height: 1.15,
      color: c.paper,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontSize: 24,
      fontWeight: FontWeight.w700,
      letterSpacing: -0.4,
      height: 1.25,
      color: c.paper,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontSize: 18,
      fontWeight: FontWeight.w600,
      letterSpacing: -0.2,
      height: 1.3,
      color: c.paper,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 13,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.1,
      color: c.paper,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w500,
      letterSpacing: 0.4,
      color: c.paperDim,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.5,
      color: c.paper,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 14.5,
      height: 1.5,
      color: c.paper,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.45,
      color: c.paperDim,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 15,
      height: 1.3,
      color: c.paper,
      fontWeight: FontWeight.w600,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 14,
      color: c.paper,
      fontWeight: FontWeight.w600,
    ),
  );
}

ThemeData _build(Brightness brightness) {
  final c = Brand.forBrightness(brightness);
  final text = _buildTextTheme(c);
  final dark = brightness == Brightness.dark;

  final scheme = dark
      ? ColorScheme.dark(
          primary: c.signal,
          onPrimary: Brand.onSignal,
          primaryContainer: c.signal.withValues(alpha: 0.18),
          onPrimaryContainer: c.paper,
          secondary: c.paper,
          onSecondary: c.canvas,
          surface: c.surface,
          onSurface: c.paper,
          surfaceContainerHighest: c.surfaceHi,
          outline: c.rule,
          error: Brand.danger,
          onError: Colors.white,
        )
      : ColorScheme.light(
          primary: c.signal,
          onPrimary: Brand.onSignal,
          primaryContainer: c.signal.withValues(alpha: 0.14),
          onPrimaryContainer: c.signalInk,
          secondary: c.paper,
          onSecondary: Colors.white,
          surface: c.surface,
          onSurface: c.paper,
          surfaceContainerHighest: c.surfaceHi,
          outline: c.rule,
          error: Brand.danger,
          onError: Colors.white,
        );

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    colorScheme: scheme,
    extensions: [c],
    textTheme: text,
    iconTheme: IconThemeData(color: c.paperDim, size: 20),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.paper,
      elevation: 0,
      scrolledUnderElevation: 0,
      centerTitle: false,
      titleTextStyle: text.headlineMedium,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
        side: BorderSide(color: c.rule),
      ),
    ),
    listTileTheme: ListTileThemeData(
      iconColor: c.paperDim,
      textColor: c.paper,
      titleTextStyle: text.titleSmall,
      subtitleTextStyle: text.bodySmall,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: dark ? c.surface : c.surfaceHi,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: BorderSide(color: c.rule),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: BorderSide(color: c.rule),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: BorderSide(color: c.signal, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: const BorderSide(color: Brand.danger),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
        borderSide: const BorderSide(color: Brand.danger, width: 2),
      ),
      labelStyle: text.bodyMedium?.copyWith(color: c.paperDim),
      floatingLabelStyle: text.labelMedium?.copyWith(color: c.signalInk),
      hintStyle: text.bodyMedium?.copyWith(color: c.paperDim),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.signal,
        foregroundColor: Brand.onSignal,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.paper,
        minimumSize: const Size(0, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        side: BorderSide(color: c.rule),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radius),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.signalInk,
        minimumSize: const Size(0, 44),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radiusSm),
        ),
        textStyle: text.labelLarge,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.paperDim,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Brand.radiusSm),
        ),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radiusLg),
      ),
      titleTextStyle: text.headlineMedium,
      contentTextStyle: text.bodyMedium,
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: dark ? c.surfaceHi : Brand.brandNavy,
      contentTextStyle: GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: 13.5,
        fontWeight: FontWeight.w500,
      ),
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Brand.radius),
      ),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceHi,
      side: BorderSide(color: c.rule),
      labelStyle: text.labelMedium?.copyWith(color: c.paper),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(99),
      ),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.selected)
            ? c.signal
            : Colors.transparent,
      ),
      checkColor: WidgetStateProperty.all(Brand.onSignal),
      side: BorderSide(color: c.rule, width: 1.5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(5),
      ),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith(
        (s) => s.contains(WidgetState.selected) ? Brand.onSignal : c.surface,
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
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Brand.brandNavy,
        borderRadius: BorderRadius.circular(Brand.radiusSm),
      ),
      textStyle: GoogleFonts.plusJakartaSans(
        color: Colors.white,
        fontSize: 12,
      ),
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: WidgetStateProperty.resolveWith(
        (st) => st.contains(WidgetState.hovered) ? 6 : 3.5,
      ),
      radius: const Radius.circular(4),
      thumbColor: WidgetStateProperty.resolveWith(
        (st) => c.paperDim.withValues(
          alpha: st.contains(WidgetState.dragged)
              ? 0.60
              : st.contains(WidgetState.hovered)
                  ? 0.45
                  : 0.26,
        ),
      ),
      trackColor: WidgetStateProperty.all(Colors.transparent),
      trackBorderColor: WidgetStateProperty.all(Colors.transparent),
      crossAxisMargin: 3,
      mainAxisMargin: 4,
      interactive: true,
    ),
    splashFactory: InkSparkle.splashFactory,
    highlightColor: Colors.transparent,
  );
}

ThemeData darkTheme() => _build(Brightness.dark);
ThemeData lightTheme() => _build(Brightness.light);

ThemeData buildTheme() => lightTheme();
