import 'package:flutter/material.dart';

/// 設計 UI／UX v1 棕米色票。
class EatSetTheme {
  EatSetTheme._();

  static const Color primary = Color(0xFF6B3E2E);
  static const Color onPrimary = Color(0xFFFFF8F3);
  static const Color primaryContainer = Color(0xFFF0D5C4);
  static const Color secondary = Color(0xFFA65D3F);
  static const Color secondaryContainer = Color(0xFFF6E4DA);
  static const Color surface = Color(0xFFFBF6F1);
  static const Color surfaceContainerHighest = Color(0xFFF3E6DC);
  static const Color outline = Color(0xFFD4C2B6);
  static const Color error = Color(0xFF8F2F2F);
  static const Color errorContainer = Color(0xFFF8D7D3);
  static const Color tertiaryContainer = Color(0xFFF5E6A8);
  static const Color onSurface = Color(0xFF2C211C);
  static const Color onSurfaceVariant = Color(0xFF7A6A60);

  static ThemeData light() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.light,
    );
    final scheme = base.copyWith(
      primary: primary,
      onPrimary: onPrimary,
      primaryContainer: primaryContainer,
      secondary: secondary,
      secondaryContainer: secondaryContainer,
      surface: surface,
      surfaceContainerHighest: surfaceContainerHighest,
      outline: outline,
      error: error,
      errorContainer: errorContainer,
      tertiaryContainer: tertiaryContainer,
      onSurface: onSurface,
      onSurfaceVariant: onSurfaceVariant,
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: surface,
      cardTheme: CardThemeData(
        color: surfaceContainerHighest,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
        ),
      ),
    );
  }

  static ThemeData dark() {
    final base = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: Brightness.dark,
    );
    final scheme = base.copyWith(
      primary: const Color(0xFFE8B89A),
      onPrimary: const Color(0xFF3D241C),
      surface: const Color(0xFF1C1410),
      onSurface: const Color(0xFFF5EBE3),
    );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
    );
  }
}
