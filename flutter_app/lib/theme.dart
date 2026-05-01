import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TinkerPro brand tokens — warm-dark canvas edition.
///
/// The palette has moved from "printed manual" (paper background) to
/// "editorial dark" (warm black canvas, orange rationed to signal moments,
/// everything else in off-white + hairlines). This is the change that pushes
/// the UI from industrial-utilitarian into premium-editorial.
class Brand {
  Brand._();

  /// Page background. Not pure black — the slight warm tint keeps it from
  /// reading as "terminal" and makes long reading sessions easier.
  static const Color canvas = Color(0xFF0A0908);

  /// Elevated card surface. Sits a hair warmer than the canvas.
  static const Color surface = Color(0xFF141311);

  /// Top-of-pile surface (modals, active rows, the `SignalButton` default).
  static const Color surfaceHi = Color(0xFF1C1B18);

  /// Primary type colour on canvas. Off-white, never pure #FFF.
  static const Color paper = Color(0xFFF5F2EB);

  /// Secondary text / labels / captions.
  static const Color paperDim = Color(0xFFA8A59D);

  /// Hairline rules — used for dividers, input underlines, card edges.
  /// Deliberately low contrast; the design leans on typography and spacing.
  static const Color rule = Color(0xFF2A2824);

  /// The only attention colour in the app. Reserved for: the globe logo,
  /// primary CTAs, focused inputs, small status dots, and the faint
  /// oversized station numeral.
  static const Color signal = Color(0xFFFF7D00);

  /// Low-opacity orange used for background washes behind signal UI elements.
  static Color signalGlow([double alpha = 0.12]) =>
      signal.withValues(alpha: alpha);
}

/// Text theme — three roles, three typefaces:
///  * Fraunces (serif)      → hero titles, screen headlines. Editorial, warm.
///  * Space Grotesk (sans)  → body copy, input values, lists.
///  * JetBrains Mono (mono) → structural labels ("STATION 03 · ONLINE"),
///                            step numbers, status tags, codes.
///
/// The serif/mono contrast is deliberate — it's what carries the "premium
/// editorial" tone. Don't swap either for a generic humanist sans.
TextTheme buildTextTheme() {
  final display = GoogleFonts.frauncesTextTheme();
  final body = GoogleFonts.spaceGroteskTextTheme();
  final mono = GoogleFonts.jetBrainsMonoTextTheme();

  return TextTheme(
    // Oversized numeral watermark (e.g. faint "01" behind a screen header).
    displayLarge: mono.displayLarge?.copyWith(
      fontSize: 220,
      fontWeight: FontWeight.w600,
      height: 0.9,
      letterSpacing: -6,
      color: Brand.signalGlow(0.08),
    ),
    // Hero title — serif, set large, negative tracking for editorial poise.
    displayMedium: display.displayMedium?.copyWith(
      fontSize: 44,
      fontWeight: FontWeight.w400,
      letterSpacing: -1.2,
      height: 1.05,
      color: Brand.paper,
    ),
    // Section / screen title — slightly smaller serif.
    headlineLarge: display.headlineLarge?.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.6,
      height: 1.1,
      color: Brand.paper,
    ),
    // Sub-section heading — serif, roman, restrained.
    headlineMedium: display.headlineMedium?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w400,
      letterSpacing: -0.3,
      color: Brand.paper,
    ),
    // Station tag ("STATION 03 · ONLINE") — mono, small caps vibe via tracking.
    labelLarge: mono.labelLarge?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w500,
      letterSpacing: 2.8,
      color: Brand.paper,
    ),
    // Field labels / tiny meta.
    labelMedium: mono.labelMedium?.copyWith(
      fontSize: 10,
      fontWeight: FontWeight.w500,
      letterSpacing: 2.2,
      color: Brand.paperDim,
    ),
    // Primary body copy.
    bodyLarge: body.bodyLarge?.copyWith(
      fontSize: 16,
      height: 1.5,
      color: Brand.paper,
    ),
    bodyMedium: body.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.55,
      color: Brand.paper,
    ),
    bodySmall: body.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.5,
      color: Brand.paperDim,
    ),
    // Form input value / list row title.
    titleMedium: body.titleMedium?.copyWith(
      fontSize: 16,
      height: 1.3,
      color: Brand.paper,
      fontWeight: FontWeight.w500,
    ),
    // Card / list primary line.
    titleSmall: body.titleSmall?.copyWith(
      fontSize: 15,
      color: Brand.paper,
      fontWeight: FontWeight.w600,
    ),
  );
}

ThemeData buildTheme() {
  final text = buildTextTheme();
  return ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    scaffoldBackgroundColor: Brand.canvas,
    canvasColor: Brand.canvas,
    colorScheme: const ColorScheme.dark(
      primary: Brand.signal,
      onPrimary: Brand.canvas,
      secondary: Brand.paper,
      onSecondary: Brand.canvas,
      surface: Brand.surface,
      onSurface: Brand.paper,
      error: Brand.signal,
      onError: Brand.canvas,
    ),
    textTheme: text,
    iconTheme: const IconThemeData(color: Brand.paper, size: 20),
    dividerTheme: const DividerThemeData(
      color: Brand.rule,
      thickness: 1,
      space: 1,
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: false,
      contentPadding: const EdgeInsets.only(top: 10, bottom: 14),
      // Underline only — never a pill. Focus goes orange and thickens.
      border: const UnderlineInputBorder(
        borderSide: BorderSide(color: Brand.rule, width: 1),
      ),
      enabledBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Brand.rule, width: 1),
      ),
      focusedBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Brand.signal, width: 2),
      ),
      errorBorder: const UnderlineInputBorder(
        borderSide: BorderSide(color: Brand.signal, width: 2),
      ),
      labelStyle: text.labelMedium,
      floatingLabelStyle: text.labelMedium?.copyWith(color: Brand.signal),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      hintStyle: text.bodyMedium?.copyWith(color: Brand.paperDim),
    ),

    snackBarTheme: SnackBarThemeData(
      backgroundColor: Brand.surfaceHi,
      contentTextStyle: GoogleFonts.jetBrainsMono(
        color: Brand.paper,
        fontSize: 12,
        letterSpacing: 1.4,
      ),
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(),
    ),

    // Remove Material defaults we don't want polluting the look.
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
  );
}
