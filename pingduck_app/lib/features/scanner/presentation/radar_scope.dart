import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../domain/discovered_device.dart';

/// Square radar: this device in the centre, others on latency rings by their
/// measured round-trip time. Positions are stable per IP. Cached devices sit
/// dimmed until they answer, then pulse once as they light up.
class RadarScope extends StatefulWidget {
  const RadarScope({super.key, required this.devices, required this.scanning, this.selfIp, this.onTap});

  final List<DiscoveredDevice> devices;
  final bool scanning;
  final String? selfIp;
  final ValueChanged<DiscoveredDevice>? onTap;

  @override
  State<RadarScope> createState() => _RadarScopeState();
}

class _RadarScopeState extends State<RadarScope> with SingleTickerProviderStateMixin {
  late final AnimationController _sweep =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
  final Map<String, DateTime> _litAt = {};
  final Map<String, bool> _wasOnline = {};
  static const _pulse = Duration(milliseconds: 1200);

  @override
  void initState() {
    super.initState();
    _track();
    _syncTicker();
  }

  @override
  void didUpdateWidget(RadarScope old) {
    super.didUpdateWidget(old);
    _track();
    _syncTicker();
  }

  void _track() {
    final now = DateTime.now();
    for (final d in widget.devices) {
      if (d.isOnline && _wasOnline[d.ip] != true) _litAt[d.ip] = now;
      _wasOnline[d.ip] = d.isOnline;
    }
  }

  /// Runs the ticker while scanning or while a pulse is still fading, and
  /// always schedules its own stop so an idle radar costs no frames.
  void _syncTicker() {
    final now = DateTime.now();
    final pulseLeft = _litAt.values
        .map((t) => _pulse - now.difference(t))
        .fold(Duration.zero, (a, b) => b > a ? b : a);
    if (widget.scanning || pulseLeft > Duration.zero) {
      if (!_sweep.isAnimating) _sweep.repeat();
    }
    if (!widget.scanning && _sweep.isAnimating) {
      Future.delayed(pulseLeft, () {
        if (mounted && !widget.scanning) _sweep.stop();
      });
    }
  }

  @override
  void dispose() {
    _sweep.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AspectRatio(
      aspectRatio: 1,
      child: LayoutBuilder(builder: (context, box) {
        final size = box.biggest;
        final placed = [
          for (final d in widget.devices)
            if (d.ip != widget.selfIp) (d, RadarGeometry.position(d, size)),
        ];
        return GestureDetector(
          onTapUp: (t) {
            final hit = placed
                .where((p) => (p.$2 - t.localPosition).distance < 24)
                .fold<(DiscoveredDevice, Offset)?>(null, (best, p) {
              if (best == null) return p;
              return (p.$2 - t.localPosition).distance < (best.$2 - t.localPosition).distance ? p : best;
            });
            if (hit != null) widget.onTap?.call(hit.$1);
          },
          child: Stack(
            children: [
              Positioned.fill(
                child: AnimatedBuilder(
                  animation: _sweep,
                  builder: (_, _) => CustomPaint(
                    painter: _RadarPainter(
                      placed: placed,
                      sweep: widget.scanning ? _sweep.value : null,
                      litAt: _litAt,
                      pulse: _pulse,
                    ),
                  ),
                ),
              ),
              Center(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: PingDuckColors.canvas,
                    border: Border.all(color: PingDuckColors.partition),
                  ),
                  padding: const EdgeInsets.all(8),
                  child: const DuckLogo(),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}

/// Maps a device to a stable spot on the scope.
abstract final class RadarGeometry {
  /// Ring boundaries as fractions of the half-width, with their latency.
  static const rings = [(0.30, 5, 'CORE'), (0.58, 15, 'LOCAL'), (0.86, 50, 'BOUNDARY')];

  /// Distance from the centre (0..1 of half-width) for a round-trip time.
  static double radiusFor(int? rttMs) {
    if (rttMs == null) return 0.94;  // never answered ICMP: outer edge
    double lerp(double a, double b, double t) => a + (b - a) * t.clamp(0.0, 1.0);
    if (rttMs <= 5) return lerp(0.16, 0.30, rttMs / 5);
    if (rttMs <= 15) return lerp(0.30, 0.58, (rttMs - 5) / 10);
    if (rttMs <= 50) return lerp(0.58, 0.86, (rttMs - 15) / 35);
    return lerp(0.86, 0.94, (rttMs - 50) / 200);
  }

  /// Golden-angle spread on the last octet keeps neighbours apart.
  static double angleFor(String ip) {
    final octet = int.tryParse(ip.split('.').last) ?? 0;
    return (octet * 2.399963) % (2 * math.pi);
  }

  static Offset position(DiscoveredDevice d, Size size) {
    final half = size.shortestSide / 2;
    final a = angleFor(d.ip);
    final dir = Offset(math.cos(a), math.sin(a));
    // Project onto the square ring (Chebyshev distance), matching the scope.
    final scale = 1 / math.max(dir.dx.abs(), dir.dy.abs());
    final r = radiusFor(d.isOnline ? (d.rttMs ?? d.rttHistory.lastOrNull) : d.rttHistory.lastOrNull) * half;
    return size.center(Offset.zero) + dir * scale * r;
  }
}

class _RadarPainter extends CustomPainter {
  _RadarPainter({required this.placed, required this.sweep, required this.litAt, required this.pulse});

  final List<(DiscoveredDevice, Offset)> placed;
  final double? sweep;
  final Map<String, DateTime> litAt;
  final Duration pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final half = size.shortestSide / 2;
    final frame = Paint()
      ..color = PingDuckColors.partition
      ..style = PaintingStyle.stroke;
    canvas.drawRect(Offset.zero & size, Paint()..color = PingDuckColors.canvas);
    canvas.drawRect((Offset.zero & size).deflate(0.5), frame);

    // Crosshair.
    final guide = Paint()..color = PingDuckColors.hairline;
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), guide);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), guide);

    // Dashed square rings with labels.
    for (final (frac, ms, name) in RadarGeometry.rings) {
      final r = frac * half;
      _dashedRect(canvas, Rect.fromCenter(center: c, width: 2 * r, height: 2 * r), PingDuckColors.partition);
      _label(canvas, '${ms}ms $name', Offset(c.dx, c.dy - r + 4), PdText.labelSm.copyWith(color: PingDuckColors.inkMuted),
          centered: true);
    }

    // Sweep arm.
    if (sweep != null) {
      final a = sweep! * 2 * math.pi - math.pi / 2;
      final end = c + Offset(math.cos(a), math.sin(a)) * half * 1.42;
      canvas.save();
      canvas.clipRect(Offset.zero & size);
      canvas.drawLine(c, end, Paint()
        ..color = PingDuckColors.live
        ..strokeWidth = 1.5);
      canvas.restore();
    }

    final now = DateTime.now();
    final taken = <Rect>[];
    for (final (d, p) in placed) {
      final color = !d.isOnline
          ? PingDuckColors.inkMuted
          : d.hasPrivateMac
              ? PingDuckColors.critical
              : PingDuckColors.forOnline(d.rttMs);

      final lit = litAt[d.ip];
      if (d.isOnline && lit != null) {
        final t = now.difference(lit).inMilliseconds / pulse.inMilliseconds;
        if (t < 1) {
          canvas.drawRect(
            Rect.fromCenter(center: p, width: 10 + 26 * t, height: 10 + 26 * t),
            Paint()
              ..color = color.withValues(alpha: 1 - t)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 1.5,
          );
        }
      }
      canvas.drawRect(Rect.fromCenter(center: p, width: 9, height: 9), Paint()..color = color);

      final label = d.rttMs != null && d.isOnline ? '${d.shortIp} ${d.rttMs}ms' : d.shortIp;
      _tag(canvas, label, p, size, taken, dim: !d.isOnline);
    }
  }

  void _dashedRect(Canvas canvas, Rect r, Color color) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1;
    const dash = 4.0, gap = 4.0;
    void line(Offset a, Offset b) {
      final len = (b - a).distance;
      final dir = (b - a) / len;
      for (var s = 0.0; s < len; s += dash + gap) {
        canvas.drawLine(a + dir * s, a + dir * math.min(s + dash, len), paint);
      }
    }

    line(r.topLeft, r.topRight);
    line(r.topRight, r.bottomRight);
    line(r.bottomRight, r.bottomLeft);
    line(r.bottomLeft, r.topLeft);
  }

  void _label(Canvas canvas, String text, Offset at, TextStyle style, {bool centered = false}) {
    final tp = TextPainter(text: TextSpan(text: text, style: style), textDirection: TextDirection.ltr)..layout();
    tp.paint(canvas, centered ? at - Offset(tp.width / 2, 0) : at);
  }

  /// Draws a label next to [p], trying the four corners around the marker
  /// and keeping the first spot that overlaps no earlier label.
  void _tag(Canvas canvas, String text, Offset p, Size size, List<Rect> taken, {required bool dim}) {
    final tp = TextPainter(
      text: TextSpan(text: text, style: PdText.code.copyWith(color: dim ? PingDuckColors.inkSecondary : PingDuckColors.canvas, fontSize: 11)),
      textDirection: TextDirection.ltr,
    )..layout();
    final w = tp.width + 8, h = tp.height + 4;
    final candidates = [
      Offset(p.dx + 8, p.dy - h - 2),
      Offset(p.dx + 8, p.dy + 4),
      Offset(p.dx - w - 8, p.dy - h - 2),
      Offset(p.dx - w - 8, p.dy + 4),
    ];
    final bounds = Offset.zero & size;
    Rect place(Offset o) => Rect.fromLTWH(o.dx, o.dy, w, h);
    final rect = candidates.map(place).firstWhere(
          (r) => bounds.contains(r.topLeft) && bounds.contains(r.bottomRight) && !taken.any(r.overlaps),
          orElse: () => place(candidates.first),
        );
    taken.add(rect);
    final at = rect.topLeft;
    canvas.drawRect(rect, Paint()..color = dim ? PingDuckColors.surface2 : PingDuckColors.ink);
    if (dim) {
      canvas.drawRect(rect, Paint()
        ..color = PingDuckColors.hairline
        ..style = PaintingStyle.stroke);
    }
    tp.paint(canvas, at + const Offset(4, 2));
  }

  @override
  bool shouldRepaint(covariant _RadarPainter old) => true;
}
