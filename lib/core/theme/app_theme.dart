import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final surface = dark ? EdColors.darkSurface : Colors.white;
    final ink = dark ? const Color(0xFFE8F0F4) : const Color(0xFF152F40);
    final line = dark ? EdColors.darkLine : const Color(0xFFE2EAEE);

    final scheme = ColorScheme.fromSeed(seedColor: EdColors.blue, brightness: b)
        .copyWith(
      primary: dark ? EdColors.turquoise : EdColors.blue,
      secondary: EdColors.red,
      surface: surface,
      onSurface: ink,
      outline: line,
    );

    final base = ThemeData(brightness: b, colorScheme: scheme, useMaterial3: true);
    final body = GoogleFonts.dmSansTextTheme(base.textTheme)
        .apply(bodyColor: ink, displayColor: ink);
    TextStyle head(TextStyle? s, double size) => GoogleFonts.manrope(
          textStyle: s,
          fontWeight: FontWeight.w800,
          fontSize: size,
          letterSpacing: -0.5,
          color: ink,
        );
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(12));
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      scaffoldBackgroundColor: dark ? EdColors.darkBg : EdColors.bg,
      textTheme: body.copyWith(
        headlineLarge: head(body.headlineLarge, 28),
        headlineMedium: head(body.headlineMedium, 22),
        titleLarge: head(body.titleLarge, 18),
        titleMedium: head(body.titleMedium, 16),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        shape: Border(bottom: BorderSide(color: line)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(17),
          side: BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: EdColors.red,
          foregroundColor: Colors.white,
          minimumSize: const Size.fromHeight(48),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(48),
          foregroundColor: ink,
          side: BorderSide(color: line),
          shape: shape,
          textStyle: const TextStyle(fontWeight: FontWeight.w800),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        border: border(line),
        enabledBorder: border(line),
        focusedBorder: border(EdColors.blue, 1.5),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        indicatorColor: EdColors.red.withValues(alpha: 0.12),
      ),
      dividerColor: line,
    );
  }
}
