import 'package:flutter/material.dart';

/// TinkerPro brand palette — mirrors the staff Flutter app + the web portal
/// so the customer experience reads as part of the same product family.
class Brand {
  Brand._();

  // Primary accents
  static const signal = Color(0xFFFF7D00);
  static const signalSoft = Color(0xFFFF9433);
  static const ink = Color(0xFF0F0F0F);

  // Neutrals
  static const canvas = Color(0xFFFFFFFF);
  static const paper = Color(0xFFFFFFFF);
  static const surface = Color(0xFFF7F7F5);
  static const stroke = Color(0xFFE2E8F0);
  static const subtle = Color(0xFFF1F5F9);

  // Text
  static const textPrimary = Color(0xFF0F172A);
  static const textMuted = Color(0xFF64748B);

  // States
  static const success = Color(0xFF10B981);
  static const danger = Color(0xFFDC2626);
  static const warning = Color(0xFFF59E0B);

  static Color signalGlow(double a) => signal.withValues(alpha: a);

  static Gradient get primary => const LinearGradient(
        colors: [signalSoft, signal],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static Gradient get hero => const LinearGradient(
        colors: [Color(0xFF0F0F0F), Color(0xFF000000)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}

ThemeData buildTheme() {
  final base = ThemeData.light(useMaterial3: true);
  return base.copyWith(
    colorScheme: ColorScheme.fromSeed(
      seedColor: Brand.signal,
      primary: Brand.signal,
      secondary: Brand.signalSoft,
      surface: Brand.canvas,
    ),
    scaffoldBackgroundColor: Brand.surface,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: Brand.textPrimary,
      elevation: 0,
      centerTitle: false,
    ),
    textTheme: base.textTheme.apply(
      bodyColor: Brand.textPrimary,
      displayColor: Brand.textPrimary,
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: Brand.canvas,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.stroke),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.stroke),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Brand.signal, width: 1.6),
      ),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: Brand.signal,
        foregroundColor: Colors.white,
        elevation: 0,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        ),
        textStyle: const TextStyle(
            fontSize: 14, fontWeight: FontWeight.w700, letterSpacing: 0.2),
      ),
    ),
    cardTheme: CardThemeData(
      color: Brand.canvas,
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Brand.stroke),
      ),
    ),
  );
}
