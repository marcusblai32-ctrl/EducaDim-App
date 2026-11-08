import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'colors.dart';

class AppTheme {
  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness b) {
    final dark = b == Brightness.dark;
    final primary = dark ? EdColors.darkPrimary : EdColors.blue;
    final secondary = dark ? EdColors.darkRed : EdColors.red;
    final surface = dark ? EdColors.darkSurface : Colors.white;
    final bg = dark ? EdColors.darkBg : EdColors.bg;
    final ink = dark ? const Color(0xFFEEF0FF) : EdColors.ink;
    final line = dark ? EdColors.darkLine : EdColors.line;

    final scheme = ColorScheme.fromSeed(seedColor: EdColors.blue, brightness: b).copyWith(
      primary: primary,
      onPrimary: dark ? EdColors.darkBg : Colors.white,
      secondary: secondary,
      surface: surface,
      onSurface: ink,
      outline: line,
      error: secondary,
    );

    final base = ThemeData(brightness: b, colorScheme: scheme, useMaterial3: true);
    final body = GoogleFonts.dmSansTextTheme(base.textTheme).apply(bodyColor: ink, displayColor: ink);
    TextStyle head(TextStyle? s, double size, [FontWeight w = FontWeight.w800]) => GoogleFonts.manrope(
          textStyle: s,
          fontWeight: w,
          fontSize: size,
          letterSpacing: -0.4,
          height: 1.2,
          color: ink,
        );

    final r14 = RoundedRectangleBorder(borderRadius: BorderRadius.circular(14));
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: c, width: w),
        );

    return base.copyWith(
      splashFactory: NoSplash.splashFactory, // aucun effet d'ondulation
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: _NoTransitionBuilder(),
        TargetPlatform.iOS: _NoTransitionBuilder(),
        TargetPlatform.linux: _NoTransitionBuilder(),
        TargetPlatform.macOS: _NoTransitionBuilder(),
        TargetPlatform.windows: _NoTransitionBuilder(),
      }),
      scaffoldBackgroundColor: bg,
      textTheme: body.copyWith(
        headlineLarge: head(body.headlineLarge, 28),
        headlineMedium: head(body.headlineMedium, 22),
        titleLarge: head(body.titleLarge, 18),
        titleMedium: head(body.titleMedium, 16, FontWeight.w700),
        titleSmall: head(body.titleSmall, 14, FontWeight.w700),
        bodyMedium: body.bodyMedium?.copyWith(height: 1.45),
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: surface,
        foregroundColor: ink,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: head(body.titleLarge, 18),
        shape: Border(bottom: BorderSide(color: line)),
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: line),
        ),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: primary,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: primary,
          foregroundColor: dark ? EdColors.darkBg : Colors.white,
          minimumSize: const Size.fromHeight(52),
          shape: r14,
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w800, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size.fromHeight(52),
          foregroundColor: ink,
          side: BorderSide(color: line, width: 1.2),
          shape: r14,
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: primary,
          textStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: border(line),
        enabledBorder: border(line),
        focusedBorder: border(primary, 1.8),
        errorBorder: border(secondary),
        focusedErrorBorder: border(secondary, 1.8),
        labelStyle: TextStyle(color: ink.withValues(alpha: 0.65)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: primary.withValues(alpha: 0.14),
        side: BorderSide(color: line),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        labelStyle: GoogleFonts.dmSans(fontWeight: FontWeight.w700, color: ink),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        indicatorColor: primary.withValues(alpha: 0.14),
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStatePropertyAll(
            GoogleFonts.dmSans(fontSize: 11.5, fontWeight: FontWeight.w700, color: ink)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? const Color(0xFF232A5C) : EdColors.navy,
        contentTextStyle: GoogleFonts.dmSans(color: Colors.white, fontWeight: FontWeight.w600),
        shape: r14,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(26))),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: secondary,
        foregroundColor: Colors.white,
        elevation: 3,
        shape: const CircleBorder(),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(color: primary, linearTrackColor: line),
      dividerColor: line,
      dividerTheme: DividerThemeData(color: line, space: 1),
    );
  }
}

/// Changement de page instantané (aucune animation).
class _NoTransitionBuilder extends PageTransitionsBuilder {
  const _NoTransitionBuilder();
  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}
