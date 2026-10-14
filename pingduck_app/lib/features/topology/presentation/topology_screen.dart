import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../device_details/application/diagnostics_controller.dart';
import '../../scanner/application/scan_controller.dart';
import '../../scanner/domain/device_kind.dart';
import '../../scanner/domain/discovered_device.dart';
import '../../scanner/presentation/overview_screen.dart' show inspect;
import '../../scanner/presentation/radar_scope.dart' show RadarGeometry;

final _groupProvider = NotifierProvider<_Group, String>(_Group.new);
final _focusProvider = NotifierProvider<_Focus, String?>(_Focus.new);

class _Group extends Notifier<String> {
  @override
  String build() => 'All';
  void set(String g) => state = g;
}

class _Focus extends Notifier<String?> {
  @override
  String? build() => null;
  void set(String? ip) => state = ip;
}

/// Devices arranged around the gateway by measured latency. Physical links
/// (switch ports, Wi-Fi band) are not observable from a phone, so the map
/// draws only what was measured: distance = round-trip time.
class TopologyScreen extends ConsumerWidget {
  const TopologyScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final group = ref.watch(_groupProvider);
    final focusIp = ref.watch(_focusProvider);

    final all = scan.sortedDevices.where((d) => d.ip != scan.lan?.ip).toList();
    final counts = <String, int>{};
    for (final d in all) {
      final g = scan.kindOf(d).group;
      counts[g] = (counts[g] ?? 0) + 1;
    }
    final shown = group == 'All' ? all : all.where((d) => scan.kindOf(d).group == group).toList();
    final gatewayIp = scan.lan?.gateway;
    final focus = scan.devices[focusIp] ?? (shown.isNotEmpty ? shown.first : null);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PdPanel(
          child: Row(children: [
            const Icon(Icons.call_split, color: PingDuckColors.route),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('ACTIVE SUBNET', style: PdText.labelMd),
                const SizedBox(height: 4),
                Text(scan.lan?.cidr ?? 'Scan to map', style: PdText.headlineSm, overflow: TextOverflow.ellipsis),
              ]),
            ),
            PdChip('${all.where((d) => d.isOnline).length}/${all.length} up', tone: PdTone.live),
          ]),
        ),
        const SizedBox(height: 12),
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (final g in ['All', ...counts.keys.toList()..sort()])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () => ref.read(_groupProvider.notifier).set(g),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: g == group ? PingDuckColors.ink : PingDuckColors.surface1,
                        border: Border.all(color: g == group ? PingDuckColors.ink : PingDuckColors.partition),
                      ),
                      child: Text('$g (${g == 'All' ? all.length : counts[g]})',
                          style: PdText.labelLg.copyWith(color: g == group ? PingDuckColors.canvas : PingDuckColors.ink)),
                    ),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            color: PingDuckColors.surface1,
            border: Border.all(color: PingDuckColors.partition),
          ),
          child: AspectRatio(
            aspectRatio: 1,
            child: shown.isEmpty
                ? Center(child: Text('No devices yet. Run a scan from Overview.', style: PdText.bodySm))
                : _TopologyMap(
                    devices: shown,
                    gatewayIp: gatewayIp,
                    kindOf: scan.kindOf,
                    focusIp: focus?.ip,
                    onTap: (d) => ref.read(_focusProvider.notifier).set(d.ip),
                  ),
          ),
        ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(color: PingDuckColors.partition),
              right: BorderSide(color: PingDuckColors.partition),
              bottom: BorderSide(color: PingDuckColors.partition),
            ),
          ),
          child: Text(
            'RINGS = ROUND-TRIP TIME. PHYSICAL LINKS AND WI-FI BANDS NEED THE AGENT.',
            style: PdText.labelSm.copyWith(color: PingDuckColors.inkMuted),
          ),
        ),
        const SizedBox(height: 16),
        if (focus != null) _FocusCard(device: focus, kind: scan.kindOf(focus), broadcast: scan.lan?.broadcast),
      ],
    );
  }
}

class _TopologyMap extends StatelessWidget {
  const _TopologyMap({
    required this.devices,
    required this.gatewayIp,
    required this.kindOf,
    required this.focusIp,
    required this.onTap,
  });

  final List<DiscoveredDevice> devices;
  final String? gatewayIp;
  final DeviceKind Function(DiscoveredDevice) kindOf;
  final String? focusIp;
  final ValueChanged<DiscoveredDevice> onTap;

  static const _node = 40.0;
  static const _label = 76.0;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, box) {
      final size = box.biggest;
      final c = size.center(Offset.zero);
      final half = size.shortestSide / 2 - _node * 0.75;
      final positions = <String, Offset>{};
      for (final d in devices) {
        if (d.ip == gatewayIp) {
          positions[d.ip] = c;
          continue;
        }
        final rtt = d.isOnline ? d.rttMs : d.rttHistory.lastOrNull;
        final r = _radius(rtt) * half;
        final octet = int.tryParse(d.ip.split('.').last) ?? 0;
        final a = (octet * 2.399963) % (2 * math.pi);
        positions[d.ip] = c + Offset(math.cos(a), math.sin(a)) * r;
      }
      return Stack(children: [
        Positioned.fill(child: CustomPaint(painter: _MapPainter(positions, devices, gatewayIp, half))),
        for (final d in devices)
          Positioned(
            // Kept inside the map so edge labels are not clipped.
            left: (positions[d.ip]!.dx - _label / 2).clamp(0.0, size.width - _label),
            top: (positions[d.ip]!.dy - _node / 2).clamp(0.0, size.height - _node - 20),
            width: _label,
            child: GestureDetector(
              onTap: () => onTap(d),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                _NodeBox(device: d, kind: kindOf(d), focused: d.ip == focusIp, isGateway: d.ip == gatewayIp),
                const SizedBox(height: 2),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 1),
                  decoration: BoxDecoration(
                    color: PingDuckColors.canvas,
                    border: Border.all(color: d.ip == focusIp ? PingDuckColors.keyline : PingDuckColors.hairline),
                  ),
                  child: Text(
                    d.displayName == d.ip ? d.shortIp : d.displayName,
                    style: PdText.code.copyWith(fontSize: 10, color: d.isOnline ? PingDuckColors.ink : PingDuckColors.inkMuted),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ]),
            ),
          ),
      ]);
    });
  }

  /// Same logarithmic latency scale as the Overview radar.
  static double _radius(int? rtt) => RadarGeometry.radiusFor(rtt);
}

class _MapPainter extends CustomPainter {
  _MapPainter(this.positions, this.devices, this.gatewayIp, this.half);
  final Map<String, Offset> positions;
  final List<DiscoveredDevice> devices;
  final String? gatewayIp;
  final double half;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final guide = Paint()..color = PingDuckColors.hairline;
    canvas.drawLine(Offset(c.dx, 0), Offset(c.dx, size.height), guide);
    canvas.drawLine(Offset(0, c.dy), Offset(size.width, c.dy), guide);
    for (final (ms, _) in RadarGeometry.ringMs) {
      final f = RadarGeometry.radiusFor(ms);
      final label = '${ms}ms';
      canvas.drawCircle(c, f * half, Paint()
        ..color = PingDuckColors.partition
        ..style = PaintingStyle.stroke);
      final tp = TextPainter(
        text: TextSpan(text: label, style: PdText.labelSm.copyWith(color: PingDuckColors.inkMuted)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c + Offset(4, -f * half - tp.height - 2));
    }
    final gw = gatewayIp == null ? null : positions[gatewayIp];
    if (gw == null) return;
    for (final d in devices) {
      if (d.ip == gatewayIp || !d.isOnline) continue;
      final p = positions[d.ip]!;
      // Faint spoke: reached through the gateway, not a known physical link.
      final paint = Paint()
        ..color = PingDuckColors.forOnline(d.rttMs).withValues(alpha: 0.45)
        ..strokeWidth = 1;
      final len = (p - gw).distance;
      final dir = (p - gw) / len;
      for (var s = 0.0; s < len; s += 8) {
        canvas.drawLine(gw + dir * s, gw + dir * math.min(s + 4, len), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant _MapPainter old) => true;
}

class _NodeBox extends StatelessWidget {
  const _NodeBox({required this.device, required this.kind, required this.focused, required this.isGateway});
  final DiscoveredDevice device;
  final DeviceKind kind;
  final bool focused;
  final bool isGateway;

  @override
  Widget build(BuildContext context) {
    final color = !device.isOnline
        ? PingDuckColors.inkMuted
        : device.hasPrivateMac
            ? PingDuckColors.critical
            : PingDuckColors.forOnline(device.rttMs);
    final fill = isGateway ? PingDuckColors.ink : PingDuckColors.canvas;
    return Tooltip(
      message: '${device.displayName}\n${device.ip}',
      child: Container(
        width: _TopologyMap._node,
        height: _TopologyMap._node,
        decoration: BoxDecoration(
          color: fill,
          border: Border.all(color: focused ? PingDuckColors.keyline : color, width: focused ? 2 : 1.5),
          boxShadow: focused ? const [BoxShadow(color: PingDuckColors.keyline, offset: Offset(2, 2))] : null,
        ),
        child: Icon(kind.icon, size: 20, color: isGateway ? PingDuckColors.canvas : color),
      ),
    );
  }
}

class _FocusCard extends ConsumerWidget {
  const _FocusCard({required this.device, required this.kind, this.broadcast});
  final DiscoveredDevice device;
  final DeviceKind kind;
  final String? broadcast;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = device;
    final diag = ref.watch(diagnosticsProvider(d.ip));
    return Container(
      decoration: BoxDecoration(
        color: PingDuckColors.canvas,
        border: Border.all(color: PingDuckColors.keyline, width: 2),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(color: PingDuckColors.surface1, border: Border.all(color: PingDuckColors.partition)),
            child: Icon(kind.icon, color: PingDuckColors.ink),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(d.displayName, style: PdText.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text(d.ip, style: PdText.codeLg.copyWith(color: PingDuckColors.route)),
            ]),
          ),
          PdChip(
            d.isOnline && d.rttMs != null ? '${d.rttMs} ms' : (d.isOnline ? 'online' : 'offline'),
            tone: d.isOnline ? PdTone.live : PdTone.neutral,
            icon: Icons.speed,
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(child: PdField(label: 'Kind', value: kind.label)),
          const SizedBox(width: 8),
          Expanded(child: PdField(label: 'Services', value: '${d.services.length} seen')),
        ]),
        const SizedBox(height: 8),
        Row(children: [
          Expanded(child: PdField(label: 'Vendor', value: d.vendorName ?? '—')),
          const SizedBox(width: 8),
          Expanded(
            child: PdField(
              label: 'Live ping',
              value: diag.replies.isEmpty ? '—' : '${diag.avgRtt!.toStringAsFixed(1)} ms',
              sub: diag.jitter == null ? null : '±${diag.jitter!.toStringAsFixed(1)} ms jitter',
            ),
          ),
        ]),
        const SizedBox(height: 12),
        Row(children: [
          Expanded(
            child: PdButton(
              label: 'Inspect',
              icon: Icons.manage_search,
              style: PdButtonStyle.primary,
              onPressed: () => inspect(ref, d),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PdButton(
              label: 'WOL',
              icon: Icons.power_settings_new,
              onPressed: d.mac == null
                  ? null
                  : () => ref.read(diagnosticsProvider(d.ip).notifier).wake(d.mac!, broadcast: broadcast),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: PdButton(
              label: diag.pingRunning ? 'Stop' : 'Ping',
              icon: Icons.network_ping,
              onPressed: ref.read(diagnosticsProvider(d.ip).notifier).togglePing,
            ),
          ),
        ]),
      ]),
    );
  }
}
