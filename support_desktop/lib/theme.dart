import 'package:flutter/material.dart';

// Brand typefaces are bundled as assets (see pubspec `fonts:`). We reference
// them by family name rather than via google_fonts, whose runtime loader reads
// AssetManifest.bin on every font resolution — that read fails after a hot
// restart on desktop (known Flutter bug), spamming "Unable to load asset:
// AssetManifest.bin". Bundled fonts use FontManifest.json instead and are
// immune to it.
const String _kDisplayFamily = 'Fraunces';
const String _kBodyFamily = 'SpaceGrotesk';
const String _kMonoFamily = 'JetBrainsMono';

/// TinkerPro brand tokens — now theme-aware.
///
/// Originally a class of `static const Color` fields. To support a
/// light/dark toggle without context-aware lookups, the palette has
/// moved into a [BrandColors] `ThemeExtension`. Access in widgets via:
///
///   context.brand.canvas
///
/// Old callsites that still reference `Brand.canvas` get the **dark**
/// palette's value as a fallback so legacy code doesn't break during
/// the migration — but anything that needs to flip on theme change
/// must use `context.brand.<token>`.
class Brand {
  Brand._();

  // Dark palette — teal edition (#2596BE base, per request). The base
  // background is the brand teal; cards/surfaces are deeper teals so panels
  // recede, with a lighter teal rule for dividers. Text stays near-white and
  // the signal accent stays orange (a strong complement to teal).
  static const Color _darkCanvas      = Color(0xFF2596BE);
  static const Color _darkSurface     = Color(0xFF1C7C9E);
  static const Color _darkSurfaceHi   = Color(0xFF2289AE);
  static const Color _darkPaper       = Color(0xFFFFFFFF);
  static const Color _darkPaperDim    = Color(0xFFCDE7F1);
  static const Color _darkRule        = Color(0xFF4FA9CB);
  static const Color _signal          = Color(0xFFFF7D00);

  // Light palette — warm paper edition. Canvas is a hair cream so it
  // doesn't read as a clinical Material default; rules + paperDim are
  // boosted toward slate so contrast on the bright canvas stays high.
  static const Color _lightCanvas     = Color(0xFFFAF7F1);
  static const Color _lightSurface    = Color(0xFFFFFFFF);
  static const Color _lightSurfaceHi  = Color(0xFFF3EFE7);
  static const Color _lightPaper      = Color(0xFF1A1815);
  static const Color _lightPaperDim   = Color(0xFF5F5C55);
  static const Color _lightRule       = Color(0xFFE3DED4);

  // Legacy const accessors — point at the dark palette so existing
  // code paths compile unchanged. Migrate to context.brand.* over time.
  static const Color canvas      = _darkCanvas;
  static const Color surface     = _darkSurface;
  static const Color surfaceHi   = _darkSurfaceHi;
  static const Color paper       = _darkPaper;
  static const Color paperDim    = _darkPaperDim;
  static const Color rule        = _darkRule;
  static const Color signal      = _signal;

  static Color signalGlow([double alpha = 0.12]) =>
      _signal.withValues(alpha: alpha);

  /// Build the [BrandColors] extension for a given brightness — used by
  /// [lightTheme]/[darkTheme] to register the right palette on the
  /// ThemeData so widgets can resolve `context.brand.*` against it.
  static BrandColors forBrightness(Brightness b) {
    return b == Brightness.dark
        ? const BrandColors(
            canvas:    _darkCanvas,
            surface:   _darkSurface,
            surfaceHi: _darkSurfaceHi,
            paper:     _darkPaper,
            paperDim:  _darkPaperDim,
            rule:      _darkRule,
            signal:    _signal,
          )
        : const BrandColors(
            canvas:    _lightCanvas,
            surface:   _lightSurface,
            surfaceHi: _lightSurfaceHi,
            paper:     _lightPaper,
            paperDim:  _lightPaperDim,
            rule:      _lightRule,
            signal:    _signal,
          );
  }
}

/// Active brand colors for the current theme. Registered as a
/// [ThemeExtension] so it flows through Theme.of(context) and rebuilds
/// dependents on theme change.
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
      canvas:    Color.lerp(canvas,    other.canvas,    t) ?? canvas,
      surface:   Color.lerp(surface,   other.surface,   t) ?? surface,
      surfaceHi: Color.lerp(surfaceHi, other.surfaceHi, t) ?? surfaceHi,
      paper:     Color.lerp(paper,     other.paper,     t) ?? paper,
      paperDim:  Color.lerp(paperDim,  other.paperDim,  t) ?? paperDim,
      rule:      Color.lerp(rule,      other.rule,      t) ?? rule,
      signal:    Color.lerp(signal,    other.signal,    t) ?? signal,
    );
  }
}

/// Ergonomic accessor — `context.brand.canvas` instead of the verbose
/// `Theme.of(context).extension<BrandColors>()!`. The `!` is safe here
/// because every theme this app builds registers the extension.
extension BrandContext on BuildContext {
  BrandColors get brand => Theme.of(this).extension<BrandColors>()!;
}

// ─────────────────────────────────────────────────────────────────────
// Text theme — three roles, three typefaces. Built once per brightness
// so colors flip with the active palette.

TextTheme _buildTextTheme(BrandColors c) {
  // A neutral base with every role populated, re-skinned per typeface. The
  // explicit colors below come from copyWith, so the base color is irrelevant.
  final base = Typography.material2021().black;
  final display = base.apply(fontFamily: _kDisplayFamily);
  final body = base.apply(fontFamily: _kBodyFamily);
  final mono = base.apply(fontFamily: _kMonoFamily);

  return TextTheme(
    displayLarge: mono.displayLarge?.copyWith(
      fontSize: 220,
      fontWeight: FontWeight.w600,
      height: 0.9,
      letterSpacing: -6,
      color: c.signalGlow(0.08),
    ),
    displayMedium: display.displayMedium?.copyWith(
      fontSize: 44,
      fontWeight: FontWeight.w400,
      letterSpacing: -1.2,
      height: 1.05,
      color: c.paper,
    ),
    headlineLarge: display.headlineLarge?.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.6,
      height: 1.1,
      color: c.paper,
    ),
    headlineMedium: display.headlineMedium?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.3,
      color: c.paper,
    ),
    labelLarge: mono.labelLarge?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 2.8,
      color: c.paper,
    ),
    labelMedium: mono.labelMedium?.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 2.2,
      color: c.paperDim,
    ),
    bodyLarge: body.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.5,
      color: c.paper,
    ),
    bodyMedium: body.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.55,
      color: c.paper,
    ),
    bodySmall: body.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.5,
      color: c.paperDim,
    ),
    titleMedium: body.titleMedium?.copyWith(
      fontSize: 16,
      height: 1.3,
      color: c.paper,
      fontWeight: FontWeight.w500,
    ),
    titleSmall: body.titleSmall?.copyWith(
      fontSize: 15,
      color: c.paper,
      fontWeight: FontWeight.w600,
    ),
  );
}

ThemeData _build(Brightness brightness) {
  final c = Brand.forBrightness(brightness);
  final text = _buildTextTheme(c);
  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    colorScheme: brightness == Brightness.dark
        ? ColorScheme.dark(
            primary: c.signal,
            onPrimary: c.canvas,
            secondary: c.paper,
            onSecondary: c.canvas,
            surface: c.surface,
            onSurface: c.paper,
            error: c.signal,
            onError: c.canvas,
          )
        : ColorScheme.light(
            primary: c.signal,
            onPrimary: Colors.white,
            secondary: c.paper,
            onSecondary: c.canvas,
            surface: c.surface,
            onSurface: c.paper,
            error: c.signal,
            onError: Colors.white,
          ),
    extensions: [c],
    textTheme: text,
    iconTheme: IconThemeData(color: c.paper, size: 20),
    dividerTheme: DividerThemeData(
      color: c.rule,
      thickness: 1,
      space: 1,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.only(top: 10, bottom: 14),
      border: UnderlineInputBorder(borderSide: BorderSide(color: c.rule, width: 1)),
      enabledBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.rule, width: 1)),
      focusedBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.signal, width: 2)),
      errorBorder: UnderlineInputBorder(borderSide: BorderSide(color: c.signal, width: 2)),
      labelStyle: text.labelMedium,
      floatingLabelStyle: text.labelMedium?.copyWith(color: c.signal),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintStyle: text.bodyMedium?.copyWith(color: c.paperDim),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: c.surfaceHi,
      contentTextStyle: TextStyle(
        fontFamily: _kMonoFamily,
        color: c.paper,
        fontSize: 12,
        letterSpacing: 1.4,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}

ThemeData darkTheme() => _build(Brightness.dark);
ThemeData lightTheme() => _build(Brightness.light);

/// Back-compat — older code paths still call `buildTheme()`. Points to
/// the dark theme since that was the only variant before this change.
ThemeData buildTheme() => darkTheme();
