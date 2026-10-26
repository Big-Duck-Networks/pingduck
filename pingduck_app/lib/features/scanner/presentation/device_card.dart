import 'package:flutter/material.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../domain/device_kind.dart';
import '../domain/discovered_device.dart';

/// A device list row: status rule on the leading edge, identity, latency
/// with its history, and the evidence (sources, services) behind it.
class DeviceCard extends StatelessWidget {
  const DeviceCard({
    super.key,
    required this.device,
    required this.kind,
    this.isSelf = false,
    this.onTap,
    this.onLongPress,
  });

  final DiscoveredDevice device;
  final DeviceKind kind;

  /// The phone or PC running the app.
  final bool isSelf;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final status = !d.isOnline
        ? PingDuckColors.inkMuted
        : d.hasPrivateMac
            ? PingDuckColors.critical
            : PingDuckColors.forOnline(d.rttMs);
    final ipColor = d.isOnline ? (d.hasPrivateMac ? PingDuckColors.critical : PingDuckColors.route) : PingDuckColors.inkMuted;
    final rtt = d.isOnline ? d.rttMs : null;

    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: '${d.displayName}, ${d.ip}, ${d.isOnline ? 'online' : 'offline'}',
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          decoration: BoxDecoration(
            color: d.isOnline ? theme.colorScheme.surfaceContainerLow : theme.colorScheme.surface,
            border: Border(
              left: BorderSide(color: status, width: 6),
              top: BorderSide(color: theme.colorScheme.outline),
              right: BorderSide(color: theme.colorScheme.outline),
              bottom: BorderSide(color: theme.colorScheme.outline),
            ),
          ),
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      color: theme.colorScheme.surface,
                      border: Border.all(color: theme.colorScheme.outline),
                    ),
                    child: Icon(kind.icon, color: d.isOnline ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant, size: 22),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Wrap(
                          crossAxisAlignment: WrapCrossAlignment.center,
                          spacing: 8,
                          runSpacing: 4,
                          children: [
                            Text(
                              d.displayName,
                              style: PdText.headlineSm.copyWith(
                                  color: d.isOnline ? theme.colorScheme.onSurface : theme.colorScheme.onSurfaceVariant),
                            ),
                            if (kind != DeviceKind.unknown)
                              PdChip(kind.label, uppercase: true, tone: _kindTone(kind)),
                            if (isSelf) const PdChip('THIS DEVICE', tone: PdTone.ink),
                          ],
                        ),
                        const SizedBox(height: 2),
                        // Unnamed hosts already show the IP as their title.
                        if (d.displayName != d.ip) Text(d.ip, style: PdText.codeLg.copyWith(color: ipColor)),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text.rich(TextSpan(children: [
                        TextSpan(text: rtt == null ? '—' : '$rtt', style: PdText.headlineSm.copyWith(color: status)),
                        if (rtt != null) TextSpan(text: ' ms', style: PdText.code.copyWith(color: status)),
                      ])),
                      const SizedBox(height: 4),
                      Sparkline(d.rttHistory, color: status),
                    ],
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(child: _identityLine(d)),
                  const SizedBox(width: 8),
                  Wrap(spacing: 4, children: [
                    for (final s in d.sources) PdChip(s.name.toUpperCase(), tone: _sourceTone(s)),
                  ]),
                ],
              ),
              if (d.services.isNotEmpty) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PingDuckColors.canvas,
                    border: Border.all(color: PingDuckColors.hairline),
                  ),
                  child: Text(
                    'SERVICES: ${d.services.take(4).join('  ·  ')}${d.services.length > 4 ? '  +${d.services.length - 4}' : ''}',
                    style: PdText.code.copyWith(color: PingDuckColors.inkSecondary),
                  ),
                ),
              ],
              if (d.hasPrivateMac && d.isOnline) ...[
                const SizedBox(height: 10),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: PingDuckColors.criticalFill,
                    border: Border.all(color: PingDuckColors.criticalBorder),
                  ),
                  child: Row(children: [
                    const Icon(Icons.info_outline, size: 16, color: PingDuckColors.critical),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text('Randomized hardware address. Vendor cannot be resolved.',
                          style: PdText.code.copyWith(color: PingDuckColors.critical)),
                    ),
                  ]),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// MAC and vendor when known; otherwise the vendor/model alone. Nothing is
  /// shown for facts the app does not have.
  Widget _identityLine(DiscoveredDevice d) {
    final parts = <InlineSpan>[];
    if (d.mac != null) {
      parts.add(TextSpan(text: 'MAC: ', style: PdText.code.copyWith(color: PingDuckColors.inkMuted)));
      parts.add(TextSpan(text: d.mac!.toUpperCase(), style: PdText.code));
      if (d.vendor != null && !d.hasPrivateMac) {
        parts.add(TextSpan(text: ' (${d.vendorName})', style: PdText.code.copyWith(color: PingDuckColors.route)));
      }
    } else if ((d.vendor != null && d.vendorName != d.displayName) || (d.model != null && d.model != d.displayName)) {
      final what = [
        if (d.vendorName != d.displayName) d.vendorName,
        if (d.model != d.displayName) d.model,
      ].whereType<String>().join(' · ');
      parts.add(TextSpan(text: what, style: PdText.code.copyWith(color: PingDuckColors.inkSecondary)));
    } else if (!d.isOnline && d.lastSeen != null) {
      parts.add(TextSpan(text: 'last seen ${_ago(d.lastSeen!)}', style: PdText.code.copyWith(color: PingDuckColors.inkMuted)));
    }
    return Text.rich(TextSpan(children: parts), maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  static String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }

  static PdTone _kindTone(DeviceKind k) => switch (k) {
        DeviceKind.gateway || DeviceKind.network => PdTone.live,
        DeviceKind.workstation || DeviceKind.nas || DeviceKind.virtual => PdTone.route,
        DeviceKind.iot || DeviceKind.printer => PdTone.pending,
        DeviceKind.mobile => PdTone.critical,
        _ => PdTone.neutral,
      };

  static PdTone _sourceTone(DiscoverySource s) => switch (s) {
        DiscoverySource.icmp => PdTone.route,
        DiscoverySource.mdns => PdTone.live,
        DiscoverySource.ssdp => PdTone.pending,
        DiscoverySource.arp => PdTone.live,
        DiscoverySource.dns => PdTone.neutral,
        DiscoverySource.agent => PdTone.ink,
      };
}
