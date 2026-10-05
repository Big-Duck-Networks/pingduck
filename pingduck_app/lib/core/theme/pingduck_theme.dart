import 'package:flutter/material.dart';

import 'pingduck_colors.dart';

abstract final class PingDuckTheme {
  static ThemeData dark() {
    const scheme = ColorScheme.dark(
      primary: PingDuckColors.duckYellow,
      onPrimary: PingDuckColors.techDark,
      secondary: PingDuckColors.beakOrange,
      onSecondary: PingDuckColors.techDark,
      surface: PingDuckColors.techDark,
      onSurface: PingDuckColors.textPrimary,
      surfaceContainer: PingDuckColors.techDarkRaised,
      outline: PingDuckColors.techDarkOutline,
      error: PingDuckColors.alert,
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: PingDuckColors.techDark,
      appBarTheme: const AppBarTheme(
        backgroundColor: PingDuckColors.techDark,
        foregroundColor: PingDuckColors.textPrimary,
        elevation: 0,
        centerTitle: false,
      ),
      cardTheme: const CardThemeData(
        color: PingDuckColors.techDarkRaised,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(16)),
          side: BorderSide(color: PingDuckColors.techDarkOutline),
        ),
      ),
      textTheme: ThemeData.dark().textTheme.apply(
            bodyColor: PingDuckColors.textPrimary,
            displayColor: PingDuckColors.textPrimary,
          ),
    );
  }
}
