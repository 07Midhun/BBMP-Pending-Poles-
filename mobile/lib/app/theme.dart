import 'package:flutter/material.dart';

class AppTheme {
  static const Color _darkNavy = Color(0xFF0F172A);
  static const Color _surface = Color(0xFF1E293B);
  static const Color _cyan = Color(0xFF0284C7);
  static const Color _cyanLight = Color(0xFF38BDF8);
  static const Color _green = Color(0xFF22C55E);
  static const Color _amber = Color(0xFFF59E0B);
  static const Color _red = Color(0xFFEF4444);

  static ThemeData get darkTheme {
    return ThemeData(
      brightness: Brightness.dark,
      primaryColor: _cyan,
      scaffoldBackgroundColor: _darkNavy,
      fontFamily: 'Roboto',
      colorScheme: const ColorScheme.dark(
        primary: _cyan,
        secondary: _cyanLight,
        surface: _surface,
        background: _darkNavy,
        error: _red,
      ),
      useMaterial3: true,
      appBarTheme: const AppBarTheme(
        backgroundColor: _darkNavy,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
      ),
      cardTheme: CardThemeData(
        color: _surface,
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: _cyan,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: _cyanLight,
          side: const BorderSide(color: _cyan),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 24),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: _cyanLight),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  // Helper colors
  static Color get success => _green;
  static Color get warning => _amber;
  static Color get error => _red;
  static Color get background => _darkNavy;
  static Color get surface => _surface;
  static Color get cyan => _cyan;
  static Color get cyanLight => _cyanLight;
}
