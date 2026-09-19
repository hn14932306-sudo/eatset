import 'package:flutter/material.dart';

/// B + D photo-first layout, with the sage palette from the accepted prototype.
class EatSetTheme {
  EatSetTheme._();
  static const primary = Color(0xFF3C5E38);

  static ThemeData light() => _build(Brightness.light);
  static ThemeData dark() => _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final scheme =
        ColorScheme.fromSeed(
          seedColor: primary,
          brightness: brightness,
        ).copyWith(
          primary: dark ? const Color(0xFFB3D29C) : primary,
          onPrimary: dark ? const Color(0xFF1E3318) : Colors.white,
          primaryContainer: dark
              ? const Color(0xFF34432C)
              : const Color(0xFFE8EEDF),
          surface: dark ? const Color(0xFF19211B) : const Color(0xFFF8F9F6),
          surfaceContainerLow: dark ? const Color(0xFF253129) : Colors.white,
          surfaceContainerHighest: dark
              ? const Color(0xFF34432C)
              : const Color(0xFFE8EEDF),
          onSurface: dark ? const Color(0xFFEEF4E9) : const Color(0xFF273629),
          onSurfaceVariant: dark
              ? const Color(0xFFB2C3B3)
              : const Color(0xFF637364),
          outlineVariant: dark
              ? const Color(0xFF3D5140)
              : const Color(0xFFDCE4D7),
        );
    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: scheme.surface,
      appBarTheme: AppBarTheme(
        backgroundColor: scheme.surface,
        foregroundColor: scheme.onSurface,
        surfaceTintColor: Colors.transparent,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: scheme.onSurface,
          fontSize: 22,
          fontWeight: FontWeight.w700,
          letterSpacing: 1,
        ),
      ),
      cardTheme: CardThemeData(
        color: scheme.surfaceContainerLow,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(22),
          side: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 50),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          side: BorderSide(color: scheme.outlineVariant),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: scheme.surfaceContainerLow,
        indicatorColor: scheme.primaryContainer,
        elevation: 0,
        height: 70,
      ),
    );
  }
}
