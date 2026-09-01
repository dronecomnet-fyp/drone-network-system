import 'package:flutter/material.dart';

class AppTheme {
  // Brand colors
  static const Color kPrimary = Color(0xFFD84315);
  static const Color kPrimaryDark = Color(0xFFBF360C);

  // Surfaces (kept for widgets that still reference them)
  static const Color kSurface = Color(0xFF1A1A2E);
  static const Color kSurfaceCard = Color(0xFF16213E);

  // Accents
  static const Color kAccentBlue = Color(0xFF1565C0);
  static const Color kAccentIndigo = Color(0xFF283593);

  // Semantic
  static const Color kSuccess = Color(0xFF2E7D32);
  static const Color kWarning = Color(0xFFE65100);
  static const Color kDanger = Color(0xFFC62828);

  // Text
  static const Color kTextPrimary = Colors.white;
  static const Color kTextSecondary = Colors.white70;

  // Layout
  static const double kRadius = 12.0;

  static ThemeData darkTheme() {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: Colors.white,
      colorScheme: ColorScheme.fromSeed(
        seedColor: kPrimary,
        brightness: Brightness.light,
        primary: kPrimary,
        secondary: kAccentBlue,
        surface: Colors.white,
        error: kDanger,
        onPrimary: Colors.white,
        onSurface: const Color(0xFF1A1A2E),
      ),

      // ── AppBar: brand red with rounded bottom corners ──────────────────
      appBarTheme: const AppBarTheme(
        backgroundColor: kPrimary,
        foregroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        titleTextStyle: TextStyle(
          color: Colors.white,
          fontSize: 20,
          fontWeight: FontWeight.bold,
          letterSpacing: 0.5,
        ),
        iconTheme: IconThemeData(color: Colors.white),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.only(
            bottomLeft: Radius.circular(28),
            bottomRight: Radius.circular(28),
          ),
        ),
      ),

      // ── Cards: white with subtle border/shadow ──────────────────────────
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 2,
        shadowColor: Colors.black12,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadius),
          side: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      ),

      // ── Buttons ─────────────────────────────────────────────────────────
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: kPrimary,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24.0),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
          textStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),

      // ── Inputs ──────────────────────────────────────────────────────────
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: const Color(0xFFF5F5F5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: const BorderSide(color: Color(0xFFE0E0E0)),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: const BorderSide(color: kPrimary, width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(kRadius),
          borderSide: const BorderSide(color: kDanger, width: 2),
        ),
        labelStyle: const TextStyle(color: Color(0xFF757575)),
        prefixIconColor: const Color(0xFF757575),
      ),

      // ── Navigation bar: modern floating pill style ───────────────────
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: Colors.white,
        surfaceTintColor: Colors.transparent,
        shadowColor: Colors.black26,
        elevation: 0,
        indicatorColor: kPrimary.withOpacity(0.12),
        indicatorShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: kPrimary, size: 26);
          }
          return const IconThemeData(color: Color(0xFF9E9E9E), size: 24);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              color: kPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 11,
            );
          }
          return const TextStyle(
            color: Color(0xFF9E9E9E),
            fontWeight: FontWeight.w500,
            fontSize: 11,
          );
        }),
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        height: 68,
      ),
    );
  }
}
