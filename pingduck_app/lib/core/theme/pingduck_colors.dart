import 'package:flutter/painting.dart';

/// PingDuck brand palette: "Tech Dark" surfaces with "Duck Yellow" accents.
abstract final class PingDuckColors {
  static const duckYellow = Color(0xFFFFC72C);
  static const duckYellowDim = Color(0xFF8A6D1C);
  static const beakOrange = Color(0xFFFF8A3D);

  static const techDark = Color(0xFF0D1117);
  static const techDarkRaised = Color(0xFF161B22);
  static const techDarkOutline = Color(0xFF30363D);

  static const textPrimary = Color(0xFFE6EDF3);
  static const textMuted = Color(0xFF8B949E);

  /// Device status on the radar.
  static const online = Color(0xFF3FB950);
  static const offline = Color(0xFF484F58);
  static const alert = Color(0xFFF85149);
}
