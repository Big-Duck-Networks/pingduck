import 'package:flutter/material.dart';

import 'pingduck_colors.dart';

/// Type scale from the design system. Space Grotesk carries labels, headers
/// and metrics (with tabular figures); Inter carries prose.
abstract final class PdText {
  static const _grotesk = 'SpaceGrotesk';
  static const _inter = 'Inter';
  static const _tabular = [FontFeature.tabularFigures()];

  static TextStyle get displayMobile => TextStyle(
      fontFamily: _grotesk, fontSize: 32, height: 36 / 32, fontWeight: FontWeight.w700, letterSpacing: -0.64, color: PingDuckColors.ink);
  static TextStyle get headlineLg => TextStyle(
      fontFamily: _grotesk, fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: PingDuckColors.ink);
  static TextStyle get headlineMd => TextStyle(
      fontFamily: _grotesk, fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w600, letterSpacing: -0.22, color: PingDuckColors.ink);
  static TextStyle get headlineSm => TextStyle(
      fontFamily: _grotesk, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: PingDuckColors.ink);
  static TextStyle get bodyLg => TextStyle(
      fontFamily: _inter, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400, letterSpacing: -0.16, color: PingDuckColors.ink);
  static TextStyle get bodyMd => TextStyle(
      fontFamily: _inter, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400, color: PingDuckColors.ink);
  static TextStyle get bodySm => TextStyle(
      fontFamily: _inter, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, letterSpacing: 0.12, color: PingDuckColors.inkSecondary);

  /// Labels are uppercase by convention: pass upper-cased text.
  static TextStyle get labelLg => TextStyle(
      fontFamily: _grotesk, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, letterSpacing: 0.52, color: PingDuckColors.ink);
  static TextStyle get labelMd => TextStyle(
      fontFamily: _grotesk, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600, letterSpacing: 0.66, color: PingDuckColors.inkSecondary);
  static TextStyle get labelSm => TextStyle(
      fontFamily: _grotesk, fontSize: 10, height: 12 / 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: PingDuckColors.inkSecondary);

  static TextStyle get metric => TextStyle(
      fontFamily: _grotesk, fontSize: 28, height: 32 / 28, fontWeight: FontWeight.w700, letterSpacing: -0.56,
      color: PingDuckColors.ink, fontFeatures: _tabular);
  static TextStyle get code => TextStyle(
      fontFamily: _grotesk, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, letterSpacing: 0.24,
      color: PingDuckColors.ink, fontFeatures: _tabular);
  static TextStyle get codeLg => TextStyle(
      fontFamily: _grotesk, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600,
      color: PingDuckColors.ink, fontFeatures: _tabular);
}

abstract final class PingDuckTheme {
  static const _square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: PingDuckColors.lightInk,
      onPrimary: PingDuckColors.lightCanvas,
      secondary: PingDuckColors.live,
      onSecondary: PingDuckColors.lightCanvas,
      tertiary: PingDuckColors.route,
      surface: PingDuckColors.lightCanvas,
      onSurface: PingDuckColors.lightInk,
      onSurfaceVariant: PingDuckColors.lightInkSecondary,
      surfaceContainerLowest: PingDuckColors.lightCanvas,
      surfaceContainerLow: PingDuckColors.lightSurface1,
      surfaceContainer: PingDuckColors.lightSurface1,
      surfaceContainerHigh: PingDuckColors.lightSurface2,
      outline: PingDuckColors.lightPartition,
      outlineVariant: PingDuckColors.lightHairline,
      error: PingDuckColors.critical,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: PingDuckColors.lightCanvas,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: const DividerThemeData(color: PingDuckColors.lightHairline, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: PingDuckColors.lightCanvas,
        foregroundColor: PingDuckColors.lightInk,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: PingDuckColors.lightHairline)),
        titleTextStyle: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 18,
          height: 24 / 18,
          fontWeight: FontWeight.w600,
          color: PingDuckColors.lightInk,
        ),
      ),
      cardTheme: const CardThemeData(
        color: PingDuckColors.lightCanvas,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(side: BorderSide(color: PingDuckColors.lightPartition)),
      ),
      chipTheme: const ChipThemeData(shape: _square),
      dialogTheme: const DialogThemeData(
        backgroundColor: PingDuckColors.lightCanvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(side: BorderSide(color: PingDuckColors.lightKeyline)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PingDuckColors.lightCanvas,
        surfaceTintColor: Colors.transparent,
        shape: Border(top: BorderSide(color: PingDuckColors.lightKeyline)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: PingDuckColors.lightInk,
        shape: _square,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontFamily: 'SpaceGrotesk', color: PingDuckColors.lightCanvas, fontSize: 13),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.lightPartition)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.lightPartition)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.lightKeyline)),
        isDense: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: PingDuckColors.live, linearMinHeight: 2),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: PingDuckColors.lightCanvas,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => PdText.labelSm.copyWith(
              color: s.contains(WidgetState.selected) ? PingDuckColors.live : PingDuckColors.lightInkSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? PingDuckColors.live : PingDuckColors.lightInkSecondary,
            )),
      ),
      textTheme: TextTheme(
        displaySmall: PdText.displayMobile,
        headlineLarge: PdText.headlineLg,
        headlineMedium: PdText.headlineMd,
        headlineSmall: PdText.headlineSm,
        titleLarge: PdText.headlineSm,
        titleMedium: PdText.labelLg,
        bodyLarge: PdText.bodyLg,
        bodyMedium: PdText.bodyMd,
        bodySmall: PdText.bodySm,
        labelLarge: PdText.labelLg,
        labelMedium: PdText.labelMd,
        labelSmall: PdText.labelSm,
      ),
    );
  }

  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: PingDuckColors.darkInk,
      onPrimary: PingDuckColors.darkCanvas,
      secondary: PingDuckColors.live,
      onSecondary: PingDuckColors.darkCanvas,
      tertiary: PingDuckColors.route,
      surface: PingDuckColors.darkCanvas,
      onSurface: PingDuckColors.darkInk,
      onSurfaceVariant: PingDuckColors.darkInkSecondary,
      surfaceContainerLowest: PingDuckColors.darkCanvas,
      surfaceContainerLow: PingDuckColors.darkSurface1,
      surfaceContainer: PingDuckColors.darkSurface1,
      surfaceContainerHigh: PingDuckColors.darkSurface2,
      outline: PingDuckColors.darkPartition,
      outlineVariant: PingDuckColors.darkHairline,
      error: PingDuckColors.critical,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: PingDuckColors.darkCanvas,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: const DividerThemeData(color: PingDuckColors.darkHairline, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: PingDuckColors.darkCanvas,
        foregroundColor: PingDuckColors.darkInk,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: PingDuckColors.darkHairline)),
        titleTextStyle: TextStyle(
          fontFamily: 'SpaceGrotesk',
          fontSize: 18,
          height: 24 / 18,
          fontWeight: FontWeight.w600,
          color: PingDuckColors.darkInk,
        ),
      ),
      cardTheme: const CardThemeData(
        color: PingDuckColors.darkCanvas,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(side: BorderSide(color: PingDuckColors.darkPartition)),
      ),
      chipTheme: const ChipThemeData(shape: _square),
      dialogTheme: const DialogThemeData(
        backgroundColor: PingDuckColors.darkSurface1,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(side: BorderSide(color: PingDuckColors.darkPartition)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PingDuckColors.darkSurface1,
        surfaceTintColor: Colors.transparent,
        shape: Border(top: BorderSide(color: PingDuckColors.darkHairline)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: PingDuckColors.darkSurface2,
        shape: _square,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontFamily: 'SpaceGrotesk', color: PingDuckColors.darkInk, fontSize: 13),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.darkPartition)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.darkPartition)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.darkKeyline)),
        isDense: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: PingDuckColors.live, linearMinHeight: 2),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: PingDuckColors.darkCanvas,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => PdText.labelSm.copyWith(
              color: s.contains(WidgetState.selected) ? PingDuckColors.live : PingDuckColors.darkInkSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? PingDuckColors.live : PingDuckColors.darkInkSecondary,
            )),
      ),
      textTheme: TextTheme(
        displaySmall: PdText.displayMobile,
        headlineLarge: PdText.headlineLg,
        headlineMedium: PdText.headlineMd,
        headlineSmall: PdText.headlineSm,
        titleLarge: PdText.headlineSm,
        titleMedium: PdText.labelLg,
        bodyLarge: PdText.bodyLg,
        bodyMedium: PdText.bodyMd,
        bodySmall: PdText.bodySm,
        labelLarge: PdText.labelLg,
        labelMedium: PdText.labelMd,
        labelSmall: PdText.labelSm,
      ),
    );
  }
}
