import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../constants/app_flavor.dart';
import '../theme/pingduck_colors.dart';
import '../theme/pingduck_theme.dart';

/// A structural panel: hairline frame, optional status rule on top, and an
/// uppercase header row.
class PdPanel extends StatelessWidget {
  const PdPanel({
    super.key,
    this.title,
    this.icon,
    this.trailing,
    this.accent,
    this.padding = const EdgeInsets.all(12),
    this.background,
    required this.child,
  });

  final String? title;
  final IconData? icon;
  final Widget? trailing;
  final Color? accent;
  final EdgeInsets padding;
  final Color? background;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: background ?? PingDuckColors.surface1,
        border: Border(
          top: BorderSide(color: accent ?? PingDuckColors.partition, width: accent == null ? 1 : 2),
          left: BorderSide(color: PingDuckColors.partition),
          right: BorderSide(color: PingDuckColors.partition),
          bottom: BorderSide(color: PingDuckColors.partition),
        ),
      ),
      padding: padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (title != null) ...[
            Row(
              children: [
                if (icon != null) ...[Icon(icon, size: 18, color: PingDuckColors.ink), const SizedBox(width: 8)],
                Expanded(child: Text(title!.toUpperCase(), style: PdText.labelLg)),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
          ],
          child,
        ],
      ),
    );
  }
}

/// A key/value cell: uppercase label over a value.
class PdField extends StatelessWidget {
  const PdField({super.key, required this.label, required this.value, this.sub, this.valueColor});

  final String label;
  final String value;
  final String? sub;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: PingDuckColors.canvas,
        border: Border.fromBorderSide(BorderSide(color: PingDuckColors.hairline)),
      ),
      padding: const EdgeInsets.all(10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label.toUpperCase(), style: PdText.labelSm),
          const SizedBox(height: 6),
          Text(value, style: PdText.codeLg.copyWith(color: valueColor), maxLines: 1, overflow: TextOverflow.ellipsis),
          if (sub != null) ...[
            const SizedBox(height: 2),
            Text(sub!, style: PdText.code.copyWith(color: PingDuckColors.inkSecondary), maxLines: 1, overflow: TextOverflow.ellipsis),
          ],
        ],
      ),
    );
  }
}

enum PdTone { neutral, live, pending, critical, route, ink }

/// Compact rectangular tag for status, protocols and ports.
class PdChip extends StatelessWidget {
  const PdChip(this.label, {super.key, this.tone = PdTone.neutral, this.icon, this.uppercase = false});

  final String label;
  final PdTone tone;
  final IconData? icon;
  final bool uppercase;

  @override
  Widget build(BuildContext context) {
    final (fill, border, ink) = switch (tone) {
      PdTone.neutral => (PingDuckColors.surface2, PingDuckColors.hairline, PingDuckColors.inkSecondary),
      PdTone.live => (PingDuckColors.liveFill, PingDuckColors.liveBorder, PingDuckColors.live),
      PdTone.pending => (PingDuckColors.pendingFill, PingDuckColors.pendingBorder, PingDuckColors.pending),
      PdTone.critical => (PingDuckColors.criticalFill, PingDuckColors.criticalBorder, PingDuckColors.critical),
      PdTone.route => (PingDuckColors.routeFill, PingDuckColors.routeBorder, PingDuckColors.route),
      PdTone.ink => (PingDuckColors.ink, PingDuckColors.ink, PingDuckColors.canvas),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
      decoration: BoxDecoration(color: fill, border: Border.all(color: border)),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[Icon(icon, size: 12, color: ink), const SizedBox(width: 4)],
          Text(uppercase ? label.toUpperCase() : label, style: PdText.code.copyWith(color: ink, height: 1.2)),
        ],
      ),
    );
  }
}

enum PdButtonStyle { primary, secondary, accent, destructive }

/// Square button with the system's hard offset shadow; it "presses in" by
/// moving onto its shadow.
class PdButton extends StatefulWidget {
  const PdButton({
    super.key,
    required this.label,
    this.icon,
    this.onPressed,
    this.style = PdButtonStyle.secondary,
    this.height = 44,
  });

  final String label;
  final IconData? icon;
  final VoidCallback? onPressed;
  final PdButtonStyle style;
  final double height;

  @override
  State<PdButton> createState() => _PdButtonState();
}

class _PdButtonState extends State<PdButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final (fill, ink, border) = switch (widget.style) {
      PdButtonStyle.primary => (PingDuckColors.ink, PingDuckColors.canvas, PingDuckColors.ink),
      PdButtonStyle.accent => (PingDuckColors.live, PingDuckColors.canvas, PingDuckColors.live),
      PdButtonStyle.secondary => (PingDuckColors.canvas, PingDuckColors.ink, PingDuckColors.partition),
      PdButtonStyle.destructive => (PingDuckColors.canvas, PingDuckColors.critical, PingDuckColors.critical),
    };
    final offset = _down || !enabled ? 0.0 : 2.0;
    return Semantics(
      button: true,
      enabled: enabled,
      label: widget.label,
      child: GestureDetector(
        onTapDown: enabled ? (_) => setState(() => _down = true) : null,
        onTapUp: enabled ? (_) => setState(() => _down = false) : null,
        onTapCancel: enabled ? () => setState(() => _down = false) : null,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 60),
          height: widget.height,
          transform: Matrix4.translationValues(2 - offset, 2 - offset, 0),
          decoration: BoxDecoration(
            color: enabled ? fill : PingDuckColors.surface2,
            border: Border.all(color: enabled ? border : PingDuckColors.hairline),
            boxShadow: [
              if (offset > 0 && !PingDuckColors.isDark) BoxShadow(color: PingDuckColors.keyline, offset: Offset(offset, offset)),
            ],
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (widget.icon != null) ...[
                  Icon(widget.icon, size: 18, color: enabled ? ink : PingDuckColors.inkMuted),
                  const SizedBox(width: 8),
                ],
                Text(widget.label.toUpperCase(),
                    style: PdText.labelLg.copyWith(color: enabled ? ink : PingDuckColors.inkMuted)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The PingDuck mark: a duck head in a carbon disc. In dev builds, displays the DEV badge.
class DuckLogo extends StatelessWidget {
  const DuckLogo({super.key, this.size = 40, this.isDev});
  final double size;
  final bool? isDev;

  @override
  Widget build(BuildContext context) {
    final dev = isDev ?? AppFlavor.current.isDev;
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(painter: _DuckPainter(isDev: dev, isDark: PingDuckColors.isDark)),
    );
  }
}

class _DuckPainter extends CustomPainter {
  const _DuckPainter({this.isDev = false, this.isDark = false});
  final bool isDev;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final discColor = isDark ? const Color(0xFF1E1F24) : PingDuckColors.ink;
    canvas.drawCircle(Offset(s / 2, s / 2), s / 2, Paint()..color = discColor);
    if (isDark) {
      canvas.drawCircle(
        Offset(s / 2, s / 2),
        s / 2 - 0.5,
        Paint()
          ..color = const Color(0xFF333339)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1,
      );
    }
    final duck = Paint()..color = PingDuckColors.live;

    if (isDev) {
      const scale = 0.82;
      final ox = s * (1 - scale) / 2;
      final oy = s * 0.05;
      final ds = s * scale;

      final devDuck = Paint()..color = PingDuckColors.pending;
      final devBeak = Paint()..color = PingDuckColors.live;

      canvas.drawCircle(Offset(ox + ds * 0.52, oy + ds * 0.42), ds * 0.2, devDuck);
      final body = Path()
        ..moveTo(ox + ds * 0.34, oy + ds * 0.5)
        ..quadraticBezierTo(ox + ds * 0.22, oy + ds * 0.76, ox + ds * 0.5, oy + ds * 0.78)
        ..quadraticBezierTo(ox + ds * 0.74, oy + ds * 0.78, ox + ds * 0.7, oy + ds * 0.56)
        ..close();
      canvas.drawPath(body, devDuck);
      final beak = Path()
        ..moveTo(ox + ds * 0.68, oy + ds * 0.38)
        ..lineTo(ox + ds * 0.84, oy + ds * 0.44)
        ..lineTo(ox + ds * 0.68, oy + ds * 0.5)
        ..close();
      canvas.drawPath(beak, devBeak);
      canvas.drawCircle(
        Offset(ox + ds * 0.56, oy + ds * 0.38),
        ds * 0.035,
        Paint()..color = isDark ? const Color(0xFF111827) : PingDuckColors.canvas,
      );

      // Centered DEV pill badge matching app icon & splash
      final bw = s * 0.44;
      final bh = s * 0.16;
      final bx = (s - bw) / 2;
      final by = s * 0.68;
      final r = bh / 2;
      canvas.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(bx, by, bw, bh), Radius.circular(r)),
        Paint()..color = PingDuckColors.live,
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: 'DEV',
          style: TextStyle(
            color: const Color(0xFF111827),
            fontSize: math.max(6.0, bh * 0.72),
            fontWeight: FontWeight.w800,
            fontFamily: 'SpaceGrotesk',
            letterSpacing: 0.6,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(bx + (bw - textPainter.width) / 2, by + (bh - textPainter.height) / 2),
      );
    } else {
      // Head, then body sweeping down-left, then the beak.
      canvas.drawCircle(Offset(s * 0.52, s * 0.42), s * 0.2, duck);
      final body = Path()
        ..moveTo(s * 0.34, s * 0.5)
        ..quadraticBezierTo(s * 0.22, s * 0.76, s * 0.5, s * 0.78)
        ..quadraticBezierTo(s * 0.74, s * 0.78, s * 0.7, s * 0.56)
        ..close();
      canvas.drawPath(body, duck);
      final beak = Path()
        ..moveTo(s * 0.68, s * 0.38)
        ..lineTo(s * 0.84, s * 0.44)
        ..lineTo(s * 0.68, s * 0.5)
        ..close();
      canvas.drawPath(beak, Paint()..color = PingDuckColors.pending);
      canvas.drawCircle(
        Offset(s * 0.56, s * 0.38),
        s * 0.035,
        Paint()..color = isDark ? const Color(0xFF111827) : PingDuckColors.canvas,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _DuckPainter oldDelegate) =>
      oldDelegate.isDev != isDev || oldDelegate.isDark != isDark;
}

/// Latency line for the ledger cards; null samples (timeouts) break the line.
class Sparkline extends StatelessWidget {
  const Sparkline(this.samples, {super.key, this.color = PingDuckColors.live, this.width = 56, this.height = 16});

  final List<int?> samples;
  final Color color;
  final double width;
  final double height;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: height,
        child: CustomPaint(painter: _SparkPainter(samples, color)),
      );
}

class _SparkPainter extends CustomPainter {
  _SparkPainter(this.samples, this.color);
  final List<int?> samples;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final values = samples.whereType<int>();
    if (samples.length < 2 || values.isEmpty) return;
    final maxV = math.max(1, values.reduce(math.max)).toDouble();
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    final dx = size.width / (samples.length - 1);
    Path? path;
    for (var i = 0; i < samples.length; i++) {
      final v = samples[i];
      if (v == null) {
        if (path != null) canvas.drawPath(path, paint);
        path = null;
        continue;
      }
      final p = Offset(i * dx, size.height - (v / maxV) * (size.height - 2) - 1);
      path == null ? (path = Path()..moveTo(p.dx, p.dy)) : path.lineTo(p.dx, p.dy);
    }
    if (path != null) canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparkPainter old) => old.samples != samples || old.color != color;
}

/// Section header used between panels (the device list's network name).
class PdSectionHeader extends StatelessWidget {
  const PdSectionHeader({super.key, required this.title, this.icon, this.badge, this.trailing});
  final String title;
  final IconData? icon;
  final String? badge;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final heading = Row(
      children: [
        if (icon != null) ...[Icon(icon, size: 22, color: PingDuckColors.live), const SizedBox(width: 8)],
        Flexible(child: Text(title, style: PdText.headlineMd, overflow: TextOverflow.ellipsis)),
        if (badge != null) ...[const SizedBox(width: 10), PdChip(badge!, tone: PdTone.live)],
      ],
    );
    if (trailing == null) return heading;
    // Phones are too narrow for heading and controls on one line.
    return LayoutBuilder(
      builder: (context, box) => box.maxWidth < 420
          ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              heading,
              Align(alignment: Alignment.centerRight, child: trailing),
            ])
          : Row(children: [Expanded(child: heading), trailing!]),
    );
  }
}
