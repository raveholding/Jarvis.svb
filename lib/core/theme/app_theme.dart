import 'package:flutter/material.dart';

/// Paleta "HUD": negro azulado, cian eléctrico y violeta para el razonamiento.
class JColors {
  JColors._();

  static const background = Color(0xFF05070D);
  static const surface = Color(0xFF0C111C);
  static const surfaceHigh = Color(0xFF141B2B);
  static const outline = Color(0xFF1F2940);
  static const cyan = Color(0xFF22D3EE);
  static const cyanDeep = Color(0xFF0E7490);
  static const violet = Color(0xFF8B5CF6);
  static const teal = Color(0xFF2DD4BF);
  static const amber = Color(0xFFF59E0B);
  static const red = Color(0xFFEF4444);
  static const green = Color(0xFF22C55E);
  static const textPrimary = Color(0xFFE6EDF7);
  static const textSecondary = Color(0xFF8A97AD);
  static const muted = Color(0xFF4B5568);
}

class AppTheme {
  AppTheme._();

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: JColors.cyan,
      brightness: Brightness.dark,
    ).copyWith(
      surface: JColors.surface,
      primary: JColors.cyan,
      secondary: JColors.violet,
      error: JColors.red,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: JColors.background,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        foregroundColor: JColors.textPrimary,
      ),
      cardTheme: CardThemeData(
        color: JColors.surface,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: const BorderSide(color: JColors.outline),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: JColors.surfaceHigh,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        labelStyle: const TextStyle(color: JColors.textSecondary),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: JColors.surfaceHigh,
        selectedColor: JColors.cyanDeep,
        side: const BorderSide(color: JColors.outline),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
        labelStyle: const TextStyle(color: JColors.textPrimary, fontSize: 13),
      ),
      snackBarTheme: const SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: JColors.surfaceHigh,
        contentTextStyle: TextStyle(color: JColors.textPrimary),
      ),
      textTheme: const TextTheme(
        headlineSmall: TextStyle(
          color: JColors.textPrimary,
          fontWeight: FontWeight.w700,
          letterSpacing: 4,
        ),
        titleMedium: TextStyle(color: JColors.textPrimary, fontWeight: FontWeight.w600),
        bodyMedium: TextStyle(color: JColors.textPrimary, height: 1.35),
        bodySmall: TextStyle(color: JColors.textSecondary),
      ),
    );
  }
}
