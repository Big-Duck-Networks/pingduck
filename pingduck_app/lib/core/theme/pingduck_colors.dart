import 'package:flutter/painting.dart';

/// "Precision Editorial Recon" palette: white canvas, carbon ink, hairline
/// rules, and telemetry accents reserved for status.
abstract final class PingDuckColors {
  // Canvas and containers.
  static const canvas = Color(0xFFFFFFFF);
  static const surface1 = Color(0xFFF8F9FA);
  static const surface2 = Color(0xFFF1F3F5);
  static const surfaceHover = Color(0xFFECEEF1);

  // Rules.
  static const hairline = Color(0xFFE2E5E8);
  static const partition = Color(0xFFCBD2D9);
  static const keyline = Color(0xFF111827);

  // Ink.
  static const ink = Color(0xFF111827);
  static const inkSecondary = Color(0xFF475569);
  static const inkMuted = Color(0xFF94A3B8);

  // Telemetry accents.
  static const live = Color(0xFF059669);
  static const pending = Color(0xFFD97706);
  static const critical = Color(0xFFDC2626);
  static const route = Color(0xFF2563EB);

  // Chip fills that pair with the accents.
  static const liveFill = Color(0xFFECFDF5);
  static const liveBorder = Color(0xFFA7F3D0);
  static const criticalFill = Color(0xFFFEF2F2);
  static const criticalBorder = Color(0xFFFECACA);
  static const pendingFill = Color(0xFFFFFBEB);
  static const pendingBorder = Color(0xFFFDE68A);
  static const routeFill = Color(0xFFEFF6FF);
  static const routeBorder = Color(0xFFBFDBFE);

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
