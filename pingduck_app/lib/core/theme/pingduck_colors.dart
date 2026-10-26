import 'package:flutter/painting.dart';

/// "Precision Editorial Recon" palette:
/// - Light: white canvas, carbon ink, hairline rules, and telemetry accents.
/// - Dark: pitch-black AMOLED canvas, dark elevated surfaces, thin graphite rules,
///   crisp white ink, and vivid telemetry accents matching Fing.
abstract final class PingDuckColors {
  // Light Palette
  static const lightCanvas = Color(0xFFFFFFFF);
  static const lightSurface1 = Color(0xFFF8F9FA);
  static const lightSurface2 = Color(0xFFF1F3F5);
  static const lightSurfaceHover = Color(0xFFECEEF1);
  static const lightHairline = Color(0xFFE2E5E8);
  static const lightPartition = Color(0xFFCBD2D9);
  static const lightKeyline = Color(0xFF111827);
  static const lightInk = Color(0xFF111827);
  static const lightInkSecondary = Color(0xFF475569);
  static const lightInkMuted = Color(0xFF94A3B8);

  // Dark Palette (Pitch-black AMOLED)
  static const darkCanvas = Color(0xFF000000);
  static const darkSurface1 = Color(0xFF121214);
  static const darkSurface2 = Color(0xFF1C1C20);
  static const darkSurfaceHover = Color(0xFF27272A);
  static const darkHairline = Color(0xFF26262B);
  static const darkPartition = Color(0xFF3A3A42);
  static const darkKeyline = Color(0xFFFFFFFF);
  static const darkInk = Color(0xFFFFFFFF);
  static const darkInkSecondary = Color(0xFFA1A1AA);
  static const darkInkMuted = Color(0xFF71717A);

  /// Whether dark theme is currently active. Synced dynamically in MaterialApp.builder.
  static bool isDark = false;

  // Active tokens (dynamically adapt based on theme brightness)
  static Color get canvas => isDark ? darkCanvas : lightCanvas;
  static Color get surface1 => isDark ? darkSurface1 : lightSurface1;
  static Color get surface2 => isDark ? darkSurface2 : lightSurface2;
  static Color get surfaceHover => isDark ? darkSurfaceHover : lightSurfaceHover;
  static Color get hairline => isDark ? darkHairline : lightHairline;
  static Color get partition => isDark ? darkPartition : lightPartition;
  static Color get keyline => isDark ? darkKeyline : lightKeyline;
  static Color get ink => isDark ? darkInk : lightInk;
  static Color get inkSecondary => isDark ? darkInkSecondary : lightInkSecondary;
  static Color get inkMuted => isDark ? darkInkMuted : lightInkMuted;

  // Telemetry accents (constant across both modes)
  static const live = Color(0xFF059669);
  static const pending = Color(0xFFD97706);
  static const critical = Color(0xFFDC2626);
  static const route = Color(0xFF2563EB);

  // Chip fills that pair with the accents.
  static Color get liveFill => isDark ? const Color(0xFF063327) : const Color(0xFFECFDF5);
  static Color get liveBorder => isDark ? const Color(0xFF059669) : const Color(0xFFA7F3D0);
  static Color get criticalFill => isDark ? const Color(0xFF3B0D0D) : const Color(0xFFFEF2F2);
  static Color get criticalBorder => isDark ? const Color(0xFFDC2626) : const Color(0xFFFECACA);
  static Color get pendingFill => isDark ? const Color(0xFF3A1C04) : const Color(0xFFFFFBEB);
  static Color get pendingBorder => isDark ? const Color(0xFFD97706) : const Color(0xFFFDE68A);
  static Color get routeFill => isDark ? const Color(0xFF132347) : const Color(0xFFEFF6FF);
  static Color get routeBorder => isDark ? const Color(0xFF2563EB) : const Color(0xFFBFDBFE);

  /// An online device: latency colour, or cobalt when it answered only by
  /// mDNS/SSDP and has no ICMP round trip.
  static Color forOnline(int? ms) => ms == null ? route : forRtt(ms);

  /// Latency colour: nominal under 20 ms, marginal under 100 ms.
  static Color forRtt(int? ms) => ms == null
      ? inkMuted
      : ms < 20
          ? live
          : ms < 100
              ? pending
              : critical;
}
