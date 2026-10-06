/// How a device was discovered. Mirrors the `PD_SRC_*` flags in
/// `core/include/pingduck/pingduck.h`; the bit values must stay in sync.
enum DiscoverySource {
  icmp(1 << 0),
  mdns(1 << 1),
  ssdp(1 << 2),
  arp(1 << 3),
  dns(1 << 4);

  const DiscoverySource(this.bit);
  final int bit;

  static Set<DiscoverySource> fromMask(int mask) =>
      {for (final s in values) if (mask & s.bit != 0) s};
}

/// A device on the LAN, as reported by pingduck-core (`pd_device`) and
/// enriched with history from the local cache.
class DiscoveredDevice {
  const DiscoveredDevice({
    required this.ip,
    this.mac,
    this.hostname,
    this.vendor,
    this.model,
    this.services = const [],
    this.rttMs,
    this.sources = const {},
    this.isOnline = false,
    this.firstSeen,
    this.lastSeen,
  });

  final String ip;
  final String? mac;
  final String? hostname;
  final String? vendor;
  final String? model;
  final List<String> services;
  final int? rttMs;
  final Set<DiscoverySource> sources;

  /// False for devices loaded from cache that have not answered this sweep;
  /// the radar renders those dimmed until they light up.
  final bool isOnline;
  final DateTime? firstSeen;
  final DateTime? lastSeen;

  /// Stable identity: MAC when known (survives DHCP changes), else IP.
  String get id => mac ?? ip;

  String get displayName => hostname ?? model ?? vendor ?? ip;

  /// The same device, marked as not (yet) answering the current scan.
  DiscoveredDevice offline() => DiscoveredDevice(
        ip: ip,
        mac: mac,
        hostname: hostname,
        vendor: vendor,
        model: model,
        services: services,
        sources: sources,
        firstSeen: firstSeen,
        lastSeen: lastSeen,
      );

  /// Merges a newer report for the same device, keeping known fields.
  DiscoveredDevice merge(DiscoveredDevice other) => DiscoveredDevice(
        ip: other.ip,
        mac: other.mac ?? mac,
        hostname: other.hostname ?? hostname,
        vendor: other.vendor ?? vendor,
        model: other.model ?? model,
        services: {...services, ...other.services}.toList(),
        rttMs: other.rttMs ?? rttMs,
        sources: {...sources, ...other.sources},
        isOnline: other.isOnline || isOnline,
        firstSeen: firstSeen ?? other.firstSeen,
        lastSeen: other.lastSeen ?? lastSeen,
      );
}
