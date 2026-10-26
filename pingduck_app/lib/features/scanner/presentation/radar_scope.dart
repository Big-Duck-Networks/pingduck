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
              const Positioned.fill(
                child: RepaintBoundary(child: CustomPaint(painter: _ScopeBackgroundPainter())),
              ),
              Positioned.fill(
                child: RepaintBoundary(
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
                  child: const DuckLogo(isDev: false),
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
  /// Latency scale: logarithmic from 1 ms to [maxMs], so wired hosts (1-5 ms)
  /// and Wi-Fi clients (often 50-300 ms, power saving delays replies) both
  /// spread out instead of piling onto one ring.
  static const maxMs = 500;

  /// Rings drawn on the scope, with their labels.
  static const ringMs = [(10, 'CORE'), (50, 'LOCAL'), (200, 'BOUNDARY')];

  static final Map<int, TextPainter> _captions = {};

  /// Laid-out "50ms LOCAL" style caption for a ring.
  static TextPainter ringCaption(int ms, String name) => _captions.putIfAbsent(
        ms,
        () => TextPainter(
          text: TextSpan(text: '${ms}ms $name', style: PdText.labelSm.copyWith(color: PingDuckColors.inkMuted)),
          textDirection: TextDirection.ltr,
        )..layout(),
      );

  /// Where a ring's caption sits: centred just inside the ring's top edge.
  static Rect ringCaptionRect(TextPainter tp, Offset c, double r) =>
      Rect.fromLTWH(c.dx - tp.width / 2, c.dy - r + 4, tp.width, tp.height);

  /// Distance from the centre (0..1 of half-width) for a round-trip time.
  static double radiusFor(int? rttMs) {
    if (rttMs == null) return 0.95;  // never answered ICMP: outer edge
    final f = math.log(1 + rttMs.clamp(0, maxMs)) / math.log(1 + maxMs);
    return 0.16 + 0.76 * f;
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

/// Frame, crosshair and latency rings. Never changes for a given size, so it
/// sits behind a RepaintBoundary and is rasterized once, not every frame.
class _ScopeBackgroundPainter extends CustomPainter {
  const _ScopeBackgroundPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final half = size.shortestSide / 2;
    canvas.drawRect(Offset.zero & size, Paint()..color = PingDuckColors.canvas);
    canvas.drawRect(
      (Offset.zero & size).deflate(0.5),
      Paint()
        ..color = PingDuckColors.partition
        ..style = PaintingStyle.stroke,
    );
    final guide = Paint()..color = PingDuckColors.hairline;
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), guide);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), guide);
    for (final (ms, name) in RadarGeometry.ringMs) {
      final r = RadarGeometry.radiusFor(ms) * half;
      _dashedRect(canvas, Rect.fromCenter(center: c, width: 2 * r, height: 2 * r), PingDuckColors.partition);
      final tp = RadarGeometry.ringCaption(ms, name);
      tp.paint(canvas, RadarGeometry.ringCaptionRect(tp, c, r).topLeft);
    }
  }

  static void _dashedRect(Canvas canvas, Rect r, Color color) {
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

  @override
  bool shouldRepaint(covariant _ScopeBackgroundPainter old) => false;
}

/// Sweep arm, pulses and device markers: the only per-frame work.
class _RadarPainter extends CustomPainter {
  /// Laid-out labels shared across frames.
  static final Map<String, TextPainter> _labels = {};

  _RadarPainter({required this.placed, required this.sweep, required this.litAt, required this.pulse});

  final List<(DiscoveredDevice, Offset)> placed;
  final double? sweep;
  final Map<String, DateTime> litAt;
  final Duration pulse;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final half = size.shortestSide / 2;
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
    // Labels must not cover markers or the ring captions.
    final taken = <Rect>[
      for (final (_, p) in placed) Rect.fromCenter(center: p, width: 11, height: 11),
      for (final (ms, name) in RadarGeometry.ringMs)
        RadarGeometry.ringCaptionRect(RadarGeometry.ringCaption(ms, name), c, RadarGeometry.radiusFor(ms) * half),
    ];
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

  /// Draws a label next to [p], trying the four corners around the marker
  /// and keeping the first spot inside the scope that overlaps no marker or
  /// earlier label.
  void _tag(Canvas canvas, String text, Offset p, Size size, List<Rect> taken, {required bool dim}) {
    final tp = _labels.putIfAbsent(
      '$dim|$text',
      () => TextPainter(
        text: TextSpan(
          text: text,
          style: PdText.code.copyWith(color: dim ? PingDuckColors.inkSecondary : PingDuckColors.canvas, fontSize: 11),
        ),
        textDirection: TextDirection.ltr,
      )..layout(),
    );
    if (_labels.length > 512) _labels.clear();  // labels change with RTT; keep it bounded
    final w = tp.width + 8, h = tp.height + 4;
    final candidates = [
      Offset(p.dx + 8, p.dy - h - 2),
      Offset(p.dx + 8, p.dy + 4),
      Offset(p.dx - w - 8, p.dy - h - 2),
      Offset(p.dx - w - 8, p.dy + 4),
    ];
    final bounds = (Offset.zero & size).deflate(1);
    Rect place(Offset o) => Rect.fromLTWH(o.dx, o.dy, w, h);
    bool inside(Rect r) => r.left >= bounds.left && r.top >= bounds.top && r.right <= bounds.right && r.bottom <= bounds.bottom;
    final fits = candidates.map(place).where((r) => inside(r) && !taken.any(r.overlaps));
    // In a crowded scope some labels cannot fit: show the marker alone (it is
    // still tappable) rather than stacking or clipping text.
    if (fits.isEmpty) return;
    final rect = fits.first;
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
