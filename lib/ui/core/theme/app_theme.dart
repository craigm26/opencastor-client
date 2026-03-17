/// OpenCastor app theme — M3 with brand seed color.
///
/// Brand palette:
///   Seed / primary:  #0ea5e9  (sky blue)
///   Secondary:       #2dd4bf  (teal)
///   Dark background: #0a0b1e  (midnight)
///
/// Design tokens: see [Spacing] and [AppRadius].
library;

import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  // ── Brand seed color ───────────────────────────────────────────────────────
  static const seedColor = Color(0xFF0ea5e9); // sky blue

  // ── Font ───────────────────────────────────────────────────────────────────
  static const _fontFamily = 'Inter';

  // ── Light theme ────────────────────────────────────────────────────────────
  static ThemeData get light => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.light,
        ),
        fontFamily: _fontFamily,
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 3,
        ),
        chipTheme: const ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      );

  // ── Dark theme ─────────────────────────────────────────────────────────────
  static ThemeData get dark => ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: seedColor,
          brightness: Brightness.dark,
        ),
        fontFamily: _fontFamily,
        scaffoldBackgroundColor: const Color(0xFF0a0b1e),
        cardTheme: const CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(12)),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(0, 48),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(12)),
            ),
          ),
        ),
        inputDecorationTheme: const InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.all(Radius.circular(10)),
          ),
        ),
        appBarTheme: const AppBarTheme(
          centerTitle: false,
          elevation: 0,
          scrolledUnderElevation: 3,
        ),
        chipTheme: const ChipThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
        ),
      );

  // ── Semantic / status colors ───────────────────────────────────────────────
  static const online  = Color(0xFF146C2E);  // M3 success green
  static const offline = Color(0xFF49454F);  // M3 outline
  static const warning = Color(0xFF7D5700);  // M3 warning amber
  static const danger  = Color(0xFFB3261E);  // M3 error red
  static const estop   = Color(0xFFB3261E);  // same as danger (Protocol 66)

  static Color onlineColor(bool isOnline) => isOnline ? online : offline;

  // ── Monospace text style ───────────────────────────────────────────────────
  static const mono = TextStyle(fontFamily: 'JetBrainsMono');
}

// ── Design tokens ──────────────────────────────────────────────────────────────

/// Spacing scale (dp).
class Spacing {
  const Spacing._();
  static const xs  = 4.0;
  static const sm  = 8.0;
  static const md  = 16.0;
  static const lg  = 24.0;
  static const xl  = 32.0;
  static const xxl = 48.0;
}

/// Consistent border radius values.
class AppRadius {
  const AppRadius._();
  static const sm   = Radius.circular(8);
  static const md   = Radius.circular(12);
  static const lg   = Radius.circular(16);
  static const xl   = Radius.circular(28);
  static const full = Radius.circular(999);
}
