import 'package:flutter/material.dart';

import 'pingduck_colors.dart';

/// Type scale from the design system. Space Grotesk carries labels, headers
/// and metrics (with tabular figures); Inter carries prose.
abstract final class PdText {
  static const _grotesk = 'SpaceGrotesk';
  static const _inter = 'Inter';
  static const _tabular = [FontFeature.tabularFigures()];

  static const displayMobile = TextStyle(
      fontFamily: _grotesk, fontSize: 32, height: 36 / 32, fontWeight: FontWeight.w700, letterSpacing: -0.64, color: PingDuckColors.ink);
  static const headlineLg = TextStyle(
      fontFamily: _grotesk, fontSize: 30, height: 36 / 30, fontWeight: FontWeight.w600, letterSpacing: -0.6, color: PingDuckColors.ink);
  static const headlineMd = TextStyle(
      fontFamily: _grotesk, fontSize: 22, height: 28 / 22, fontWeight: FontWeight.w600, letterSpacing: -0.22, color: PingDuckColors.ink);
  static const headlineSm = TextStyle(
      fontFamily: _grotesk, fontSize: 18, height: 24 / 18, fontWeight: FontWeight.w600, color: PingDuckColors.ink);
  static const bodyLg = TextStyle(
      fontFamily: _inter, fontSize: 16, height: 24 / 16, fontWeight: FontWeight.w400, letterSpacing: -0.16, color: PingDuckColors.ink);
  static const bodyMd = TextStyle(
      fontFamily: _inter, fontSize: 14, height: 20 / 14, fontWeight: FontWeight.w400, color: PingDuckColors.ink);
  static const bodySm = TextStyle(
      fontFamily: _inter, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w400, letterSpacing: 0.12, color: PingDuckColors.inkSecondary);

  /// Labels are uppercase by convention: pass upper-cased text.
  static const labelLg = TextStyle(
      fontFamily: _grotesk, fontSize: 13, height: 16 / 13, fontWeight: FontWeight.w600, letterSpacing: 0.52, color: PingDuckColors.ink);
  static const labelMd = TextStyle(
      fontFamily: _grotesk, fontSize: 11, height: 14 / 11, fontWeight: FontWeight.w600, letterSpacing: 0.66, color: PingDuckColors.inkSecondary);
  static const labelSm = TextStyle(
      fontFamily: _grotesk, fontSize: 10, height: 12 / 10, fontWeight: FontWeight.w700, letterSpacing: 0.8, color: PingDuckColors.inkSecondary);

  static const metric = TextStyle(
      fontFamily: _grotesk, fontSize: 28, height: 32 / 28, fontWeight: FontWeight.w700, letterSpacing: -0.56,
      color: PingDuckColors.ink, fontFeatures: _tabular);
  static const code = TextStyle(
      fontFamily: _grotesk, fontSize: 12, height: 16 / 12, fontWeight: FontWeight.w500, letterSpacing: 0.24,
      color: PingDuckColors.ink, fontFeatures: _tabular);
  static const codeLg = TextStyle(
      fontFamily: _grotesk, fontSize: 15, height: 20 / 15, fontWeight: FontWeight.w600,
      color: PingDuckColors.ink, fontFeatures: _tabular);
}

abstract final class PingDuckTheme {
  static const _square = RoundedRectangleBorder(borderRadius: BorderRadius.zero);

  static ThemeData light() {
    const scheme = ColorScheme.light(
      primary: PingDuckColors.ink,
      onPrimary: PingDuckColors.canvas,
      secondary: PingDuckColors.live,
      onSecondary: PingDuckColors.canvas,
      tertiary: PingDuckColors.route,
      surface: PingDuckColors.canvas,
      onSurface: PingDuckColors.ink,
      onSurfaceVariant: PingDuckColors.inkSecondary,
      surfaceContainerLowest: PingDuckColors.canvas,
      surfaceContainerLow: PingDuckColors.surface1,
      surfaceContainer: PingDuckColors.surface1,
      surfaceContainerHigh: PingDuckColors.surface2,
      outline: PingDuckColors.partition,
      outlineVariant: PingDuckColors.hairline,
      error: PingDuckColors.critical,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      fontFamily: 'Inter',
      scaffoldBackgroundColor: PingDuckColors.canvas,
      splashFactory: NoSplash.splashFactory,
      dividerTheme: const DividerThemeData(color: PingDuckColors.hairline, thickness: 1, space: 1),
      appBarTheme: const AppBarTheme(
        backgroundColor: PingDuckColors.canvas,
        foregroundColor: PingDuckColors.ink,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        shape: Border(bottom: BorderSide(color: PingDuckColors.hairline)),
      ),
      cardTheme: const CardThemeData(
        color: PingDuckColors.canvas,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(side: BorderSide(color: PingDuckColors.partition)),
      ),
      chipTheme: const ChipThemeData(shape: _square),
      dialogTheme: const DialogThemeData(
        backgroundColor: PingDuckColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: RoundedRectangleBorder(side: BorderSide(color: PingDuckColors.keyline)),
      ),
      bottomSheetTheme: const BottomSheetThemeData(
        backgroundColor: PingDuckColors.canvas,
        surfaceTintColor: Colors.transparent,
        shape: Border(top: BorderSide(color: PingDuckColors.keyline)),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: PingDuckColors.ink,
        shape: _square,
        behavior: SnackBarBehavior.floating,
        contentTextStyle: TextStyle(fontFamily: 'SpaceGrotesk', color: PingDuckColors.canvas, fontSize: 13),
      ),
      inputDecorationTheme: const InputDecorationTheme(
        border: OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.partition)),
        enabledBorder:
            OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.partition)),
        focusedBorder:
            OutlineInputBorder(borderRadius: BorderRadius.zero, borderSide: BorderSide(color: PingDuckColors.keyline)),
        isDense: true,
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: PingDuckColors.live, linearMinHeight: 2),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: PingDuckColors.canvas,
        surfaceTintColor: Colors.transparent,
        indicatorColor: Colors.transparent,
        height: 64,
        labelTextStyle: WidgetStateProperty.resolveWith((s) => PdText.labelSm.copyWith(
              color: s.contains(WidgetState.selected) ? PingDuckColors.live : PingDuckColors.inkSecondary,
            )),
        iconTheme: WidgetStateProperty.resolveWith((s) => IconThemeData(
              color: s.contains(WidgetState.selected) ? PingDuckColors.live : PingDuckColors.inkSecondary,
            )),
      ),
      textTheme: const TextTheme(
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
