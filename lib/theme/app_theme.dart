import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// OpenCastor app theme — brand colors from brand/USAGE.md
///
/// Brand palette:
///   Midnight Dark:   #0a0b1e   (main dark bg)
///   Midnight Light:  #f8faff   (main light bg, soft indigo tint)
///   Accent Blue:     #0ea5e9   (primary actions, gradients)
///   Accent Teal:     #2dd4bf   (secondary gradients, glow)
///   Dark Navy:       #12142b   (cards, inputs, borders in dark mode)
class AppTheme {
  AppTheme._();

  // Brand primaries
  static const brandBlue = Color(0xFF0ea5e9);
  static const brandTeal = Color(0xFF2dd4bf);
  static const midnightDark = Color(0xFF0a0b1e);
  static const midnightLight = Color(0xFFf8faff);
  static const darkNavy = Color(0xFF12142b);

  static ThemeData get light => FlexThemeData.light(
        colors: const FlexSchemeColor(
          primary: Color(0xFF0ea5e9),
          primaryContainer: Color(0xFFe0f2fe),
          secondary: Color(0xFF2dd4bf),
          secondaryContainer: Color(0xFFccfbf1),
          tertiary: Color(0xFF6366f1),
          tertiaryContainer: Color(0xFFe0e7ff),
          appBarColor: Color(0xFFf8faff),
          error: Color(0xFFef4444),
        ),
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 7,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 8,
          blendOnColors: false,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
          elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
          chipSchemeColor: SchemeColor.primaryContainer,
          cardRadius: 16,
          popupMenuRadius: 12,
          dialogRadius: 20,
          bottomSheetRadius: 24,
          inputDecoratorRadius: 10,
          inputDecoratorBorderType: FlexInputBorderType.outline,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        fontFamily: 'Inter',
      );

  static ThemeData get dark => FlexThemeData.dark(
        colors: const FlexSchemeColor(
          primary: Color(0xFF38bdf8),
          primaryContainer: Color(0xFF0369a1),
          secondary: Color(0xFF2dd4bf),
          secondaryContainer: Color(0xFF0f766e),
          tertiary: Color(0xFF818cf8),
          tertiaryContainer: Color(0xFF3730a3),
          appBarColor: Color(0xFF0a0b1e),
          error: Color(0xFFf87171),
        ),
        scaffoldBackground: midnightDark,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 18,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 22,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
          elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
          chipSchemeColor: SchemeColor.primaryContainer,
          cardRadius: 16,
          popupMenuRadius: 12,
          dialogRadius: 20,
          bottomSheetRadius: 24,
          inputDecoratorRadius: 10,
          inputDecoratorBorderType: FlexInputBorderType.outline,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        fontFamily: 'Inter',
      );

  // Semantic colors
  static const online = Color(0xFF22c55e);
  static const offline = Color(0xFF6b7280);
  static const warning = Color(0xFFf59e0b);
  static const danger = Color(0xFFef4444);
  static const estop = Color(0xFFdc2626);

  static Color onlineColor(bool isOnline) => isOnline ? online : offline;

  // Monospace text style for telemetry, RRNs, payloads
  static const mono = TextStyle(fontFamily: 'JetBrainsMono');
}
