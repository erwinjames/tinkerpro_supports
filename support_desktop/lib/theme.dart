import 'package:flutter/material.dart';

const String kFontFamily = 'SourceSansPro';

class Brand {
  Brand._();

  static const Color _darkCanvas = Color(0xFF081627);
  static const Color _darkSurface = Color(0xFF0C233E);
  static const Color _darkSurfaceHi = Color(0xFF12304F);
  static const Color _darkPaper = Color(0xFFFFFFFF);
  static const Color _darkPaperDim = Color(0xFFA7B4C4);
  static const Color _darkRule = Color(0xFF1F3A58);
  static const Color _signal = Color(0xFFFF7D00);

  static const Color _lightCanvas = Color(0xFFF5F6F8);
  static const Color _lightSurface = Color(0xFFFFFFFF);
  static const Color _lightSurfaceHi = Color(0xFFF8F9FA);
  static const Color _lightPaper = Color(0xFF0C233E);
  static const Color _lightPaperDim = Color(0xFF64748B);
  static const Color _lightRule = Color(0xFFE5E7EB);

  static const Color navy = Color(0xFF0C233E);
  static const Color navyHi = Color(0xFF14304A);
  static const Color navyRule = Color(0xFF1E3A56);
  static const Color navyText = Color(0xFFFFFFFF);
  static const Color navyMuted = Color(0xFF9AAABD);

  static const Color inputBorder = Color(0xFFD7DDE5);
  static const Color success = Color(0xFF16A34A);
  static const Color danger = Color(0xFFEF4444);
  static const Color info = Color(0xFF2563EB);
  static const Color warning = Color(0xFFF59E0B);

  static const Color canvas = _lightCanvas;
  static const Color surface = _lightSurface;
  static const Color surfaceHi = _lightSurfaceHi;
  static const Color paper = _lightPaper;
  static const Color paperDim = _lightPaperDim;
  static const Color rule = _lightRule;
  static const Color signal = _signal;

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
  final base =
      Typography.material2021().black.apply(fontFamily: kFontFamily);
  return TextTheme(
    displayLarge: base.displayLarge?.copyWith(
      fontSize: 40,
      fontWeight: FontWeight.w700,
      color: Colors.transparent,
    ),
    displayMedium: base.displayMedium?.copyWith(
      fontSize: 32,
      fontWeight: FontWeight.w700,
      height: 1.15,
      color: c.paper,
    ),
    displaySmall: base.displaySmall?.copyWith(
      fontSize: 26,
      fontWeight: FontWeight.w700,
      color: c.paper,
    ),
    headlineLarge: base.headlineLarge?.copyWith(
      fontSize: 22,
      fontWeight: FontWeight.w700,
      height: 1.2,
      color: c.paper,
    ),
    headlineMedium: base.headlineMedium?.copyWith(
      fontSize: 19,
      fontWeight: FontWeight.w700,
      color: c.paper,
    ),
    headlineSmall: base.headlineSmall?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: c.paper,
    ),
    titleLarge: base.titleLarge?.copyWith(
      fontSize: 17,
      fontWeight: FontWeight.w700,
      color: c.paper,
    ),
    titleMedium: base.titleMedium?.copyWith(
      fontSize: 15,
      height: 1.3,
      fontWeight: FontWeight.w600,
      color: c.paper,
    ),
    titleSmall: base.titleSmall?.copyWith(
      fontSize: 14,
      fontWeight: FontWeight.w600,
      color: c.paper,
    ),
    labelLarge: base.labelLarge?.copyWith(
      fontSize: 11.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.1,
      color: c.paperDim,
    ),
    labelMedium: base.labelMedium?.copyWith(
      fontSize: 11,
      fontWeight: FontWeight.w600,
      letterSpacing: 0.9,
      color: c.paperDim,
    ),
    labelSmall: base.labelSmall?.copyWith(
      fontSize: 10.5,
      fontWeight: FontWeight.w700,
      letterSpacing: 1.2,
      color: c.paperDim,
    ),
    bodyLarge: base.bodyLarge?.copyWith(
      fontSize: 15,
      height: 1.5,
      color: c.paper,
    ),
    bodyMedium: base.bodyMedium?.copyWith(
      fontSize: 14,
      height: 1.45,
      color: c.paper,
    ),
    bodySmall: base.bodySmall?.copyWith(
      fontSize: 12.5,
      height: 1.4,
      color: c.paperDim,
    ),
  );
}

ThemeData _build(Brightness brightness) {
  final c = Brand.forBrightness(brightness);
  final text = _buildTextTheme(c);
  final dark = brightness == Brightness.dark;
  final inputBorderColor = dark ? c.rule : Brand.inputBorder;
  final radius = BorderRadius.circular(6);
  OutlineInputBorder outline(Color color, [double w = 1]) => OutlineInputBorder(
      borderRadius: radius, borderSide: BorderSide(color: color, width: w));
  const buttonText = TextStyle(
    fontFamily: kFontFamily,
    fontSize: 13,
    fontWeight: FontWeight.w700,
    letterSpacing: 0.6,
  );
  final buttonShape = RoundedRectangleBorder(borderRadius: radius);
  const buttonPadding = EdgeInsets.symmetric(horizontal: 18, vertical: 12);

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    fontFamily: kFontFamily,
    visualDensity: VisualDensity.compact,
    scaffoldBackgroundColor: c.canvas,
    canvasColor: c.canvas,
    colorScheme: (dark ? const ColorScheme.dark() : const ColorScheme.light())
        .copyWith(
      primary: c.signal,
      onPrimary: Colors.white,
      secondary: dark ? Colors.white : Brand.navy,
      onSecondary: dark ? Brand.navy : Colors.white,
      surface: c.surface,
      onSurface: c.paper,
      surfaceContainerHighest: c.surfaceHi,
      surfaceContainerHigh: c.surfaceHi,
      surfaceContainer: c.surface,
      surfaceContainerLow: c.surface,
      surfaceContainerLowest: c.surface,
      outline: inputBorderColor,
      outlineVariant: c.rule,
      error: Brand.danger,
      onError: Colors.white,
      primaryContainer: c.signalGlow(0.14),
      onPrimaryContainer: c.signal,
    ),
    extensions: [c],
    textTheme: text,
    iconTheme: IconThemeData(color: c.paper, size: 20),
    dividerTheme: DividerThemeData(color: c.rule, thickness: 1, space: 1),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: c.surface,
      isDense: true,
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: outline(inputBorderColor),
      enabledBorder: outline(inputBorderColor),
      disabledBorder: outline(c.rule),
      focusedBorder: outline(c.signal, 1.5),
      errorBorder: outline(Brand.danger),
      focusedErrorBorder: outline(Brand.danger, 1.5),
      labelStyle: text.bodyMedium?.copyWith(color: c.paperDim),
      floatingLabelStyle: text.bodyMedium
          ?.copyWith(color: c.signal, fontWeight: FontWeight.w600),
      hintStyle: text.bodyMedium?.copyWith(color: c.paperDim.withValues(alpha: 0.8)),
      prefixIconColor: c.paperDim,
      suffixIconColor: c.paperDim,
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ElevatedButton.styleFrom(
        backgroundColor: c.signal,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: buttonText,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: c.signal,
        foregroundColor: Colors.white,
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: buttonText,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: c.paper,
        backgroundColor: c.surface,
        side: BorderSide(color: inputBorderColor),
        shape: buttonShape,
        padding: buttonPadding,
        textStyle: buttonText,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        foregroundColor: c.signal,
        shape: buttonShape,
        textStyle: buttonText,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(
        foregroundColor: c.paperDim,
        shape: buttonShape,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: c.signal,
      foregroundColor: Colors.white,
      elevation: 2,
    ),
    cardTheme: CardThemeData(
      color: c.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.rule),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 24,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      titleTextStyle: text.titleLarge,
      contentTextStyle: text.bodyMedium,
      barrierColor: const Color(0xFF0C233E).withValues(alpha: 0.45),
      actionsPadding: const EdgeInsets.fromLTRB(20, 8, 20, 18),
    ),
    tabBarTheme: TabBarThemeData(
      labelColor: c.signal,
      unselectedLabelColor: c.paperDim,
      indicatorColor: c.signal,
      indicatorSize: TabBarIndicatorSize.tab,
      dividerColor: c.rule,
      labelStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9),
      unselectedLabelStyle: const TextStyle(
          fontFamily: kFontFamily,
          fontSize: 13,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.9),
    ),
    dataTableTheme: DataTableThemeData(
      headingTextStyle: text.labelLarge,
      dataTextStyle: text.bodyMedium,
      headingRowColor: WidgetStatePropertyAll(c.surfaceHi),
      dividerThickness: 1,
      horizontalMargin: 16,
      columnSpacing: 24,
    ),
    listTileTheme: ListTileThemeData(
      dense: true,
      iconColor: c.paperDim,
      textColor: c.paper,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
    ),
    chipTheme: ChipThemeData(
      backgroundColor: c.surfaceHi,
      side: BorderSide(color: c.rule),
      labelStyle: text.bodySmall?.copyWith(color: c.paper),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(999)),
    ),
    checkboxTheme: CheckboxThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.signal : null),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
    ),
    radioTheme: RadioThemeData(
      fillColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.signal : c.paperDim),
    ),
    switchTheme: SwitchThemeData(
      thumbColor: const WidgetStatePropertyAll(Colors.white),
      trackColor: WidgetStateProperty.resolveWith(
          (s) => s.contains(WidgetState.selected) ? c.signal : inputBorderColor),
      trackOutlineColor: const WidgetStatePropertyAll(Colors.transparent),
    ),
    popupMenuTheme: PopupMenuThemeData(
      color: c.surface,
      surfaceTintColor: Colors.transparent,
      elevation: 8,
      textStyle: text.bodyMedium,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: c.rule),
      ),
    ),
    menuTheme: MenuThemeData(
      style: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    dropdownMenuTheme: DropdownMenuThemeData(
      menuStyle: MenuStyle(
        backgroundColor: WidgetStatePropertyAll(c.surface),
        surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
      ),
    ),
    tooltipTheme: TooltipThemeData(
      decoration: BoxDecoration(
        color: Brand.navy,
        borderRadius: BorderRadius.circular(6),
      ),
      textStyle: const TextStyle(
          fontFamily: kFontFamily, color: Colors.white, fontSize: 12),
      waitDuration: const Duration(milliseconds: 400),
    ),
    snackBarTheme: SnackBarThemeData(
      backgroundColor: Brand.navy,
      contentTextStyle: const TextStyle(
          fontFamily: kFontFamily, color: Colors.white, fontSize: 14),
      actionTextColor: c.signal,
      behavior: SnackBarBehavior.floating,
      width: 440,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      color: c.signal,
      linearTrackColor: c.rule,
    ),
    scrollbarTheme: ScrollbarThemeData(
      thickness: const WidgetStatePropertyAll(6),
      radius: const Radius.circular(6),
      thumbColor: WidgetStatePropertyAll(
          dark ? c.rule : const Color(0xFFD1D5DB)),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: c.surface,
      foregroundColor: c.paper,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: text.titleLarge,
      shape: Border(bottom: BorderSide(color: c.rule)),
    ),
    splashFactory: NoSplash.splashFactory,
    highlightColor: Colors.transparent,
    hoverColor: c.signalGlow(0.06),
  );
}

ThemeData darkTheme() => _build(Brightness.dark);
ThemeData lightTheme() => _build(Brightness.light);

ThemeData buildTheme() => darkTheme();
