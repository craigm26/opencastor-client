import 'package:flex_color_scheme/flex_color_scheme.dart';
import 'package:flutter/material.dart';

/// OpenCastor app theme — dark-first, monospace accents.
class AppTheme {
  AppTheme._();

  static const _scheme = FlexScheme.shark;

  static ThemeData get light => FlexThemeData.light(
        scheme: _scheme,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 9,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 10,
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
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        fontFamily: 'Inter',
      );

  static ThemeData get dark => FlexThemeData.dark(
        scheme: _scheme,
        surfaceMode: FlexSurfaceMode.levelSurfacesLowScaffold,
        blendLevel: 15,
        subThemesData: const FlexSubThemesData(
          blendOnLevel: 20,
          useTextTheme: true,
          useM2StyleDividerInM3: true,
          elevatedButtonSchemeColor: SchemeColor.onPrimaryContainer,
          elevatedButtonSecondarySchemeColor: SchemeColor.primaryContainer,
          chipSchemeColor: SchemeColor.primaryContainer,
          cardRadius: 16,
          popupMenuRadius: 12,
          dialogRadius: 20,
          bottomSheetRadius: 24,
        ),
        visualDensity: FlexColorScheme.comfortablePlatformDensity,
        useMaterial3: true,
        fontFamily: 'Inter',
      );

  // Semantic colors
  static const online = Color(0xFF4CAF50);
  static const offline = Color(0xFF9E9E9E);
  static const warning = Color(0xFFFFC107);
  static const danger = Color(0xFFF44336);
  static const estop = Color(0xFFD32F2F);

  static Color onlineColor(bool isOnline) => isOnline ? online : offline;

  // Monospace text style for telemetry, RRNs, payloads
  static const mono = TextStyle(fontFamily: 'JetBrainsMono');
}
