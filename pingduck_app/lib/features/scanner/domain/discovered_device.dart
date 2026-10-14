/// How a device was discovered. Mirrors the `PD_SRC_*` flags in
/// `core/include/pingduck/pingduck.h`; the bit values must stay in sync.
enum DiscoverySource {
  icmp(1 << 0),
  mdns(1 << 1),
  ssdp(1 << 2),
  arp(1 << 3),
  dns(1 << 4),

  /// App-only: reported by the homelab agent through Supabase. The core never
  /// sets it; bits 5-7 are left free for the core to grow into.
  agent(1 << 8);

  const DiscoverySource(this.bit);
  final int bit;

  static Set<DiscoverySource> fromMask(int mask) =>
      {for (final s in values) if (mask & s.bit != 0) s};

  static int toMask(Iterable<DiscoverySource> sources) => sources.fold(0, (m, s) => m | s.bit);
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
    this.customName,
    this.notes,
    this.rttHistory = const [],
    this.isKnown = false,
    this.ttl,
    this.server,
  });

  /// RTT samples kept per device (one per scan) for the ledger sparkline.
  static const historyLength = 24;

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

  /// Set by the user; never overwritten by scans.
  final String? customName;
  final String? notes;

  /// Oldest first, at most [historyLength].
  final List<int> rttHistory;

  /// Marked known by the user (Supabase `devices.is_known`): no alerts for it.
  final bool isKnown;

  /// Recognition signals (features/recognition): the TTL of the device's
  /// ping reply and its SSDP SERVER header.
  final int? ttl;
  final String? server;

  /// Stable identity: MAC when known (survives DHCP changes), else IP.
  String get id => mac ?? ip;

  String get displayName => customName ?? hostname ?? (_isServerBanner(model) ? null : model) ?? vendor ?? ip;

  /// SSDP devices without a readable description fall back to their HTTP
  /// SERVER header ("Linux/5.15, UPnP/1.0, Chromecast/1.6"): software, not a name.
  static bool _isServerBanner(String? s) => s != null && s.contains('UPnP/');

  /// Last octet, e.g. ".108", for compact radar labels.
  String get shortIp => '.${ip.split('.').last}';

  bool get hasPrivateMac => vendor?.startsWith('Private') ?? false;

  /// The same device, marked as not (yet) answering the current scan.
  DiscoveredDevice offline() => copyWith(isOnline: false, clearRtt: true);

  /// Merges a newer report for the same device, keeping known fields and the
  /// user's own name and notes.
  DiscoveredDevice merge(DiscoveredDevice other) => DiscoveredDevice(
        ip: other.ip,
        mac: other.mac ?? mac,
        hostname: other.hostname ?? hostname,
        vendor: _better(vendor, other.vendor),
        model: other.model ?? model,
        services: {...services, ...other.services}.toList(),
        rttMs: other.rttMs ?? rttMs,
        sources: {...sources, ...other.sources},
        isOnline: other.isOnline || isOnline,
        firstSeen: firstSeen ?? other.firstSeen,
        lastSeen: other.lastSeen ?? lastSeen,
        customName: customName ?? other.customName,
        notes: notes ?? other.notes,
        rttHistory: rttHistory.isNotEmpty ? rttHistory : other.rttHistory,
        // Scans never report it, so a scan must not clear it.
        isKnown: isKnown || other.isKnown,
        ttl: other.ttl ?? ttl,
        server: other.server ?? server,
      );

  /// A randomized-MAC placeholder loses to any real vendor name.
  static String? _better(String? old, String? fresh) {
    if (fresh == null) return old;
    if (old == null || old.startsWith('Private')) return fresh;
    return old;
  }

  DiscoveredDevice copyWith({
    bool? isOnline,
    int? rttMs,
    bool clearRtt = false,
    DateTime? lastSeen,
    String? customName,
    bool clearCustomName = false,
    String? notes,
    bool clearNotes = false,
    List<int>? rttHistory,
    bool? isKnown,
  }) =>
      DiscoveredDevice(
        ip: ip,
        mac: mac,
        hostname: hostname,
        vendor: vendor,
        model: model,
        services: services,
        rttMs: clearRtt ? null : rttMs ?? this.rttMs,
        sources: sources,
        isOnline: isOnline ?? this.isOnline,
        firstSeen: firstSeen,
        lastSeen: lastSeen ?? this.lastSeen,
        customName: clearCustomName ? null : customName ?? this.customName,
        notes: clearNotes ? null : notes ?? this.notes,
        rttHistory: rttHistory ?? this.rttHistory,
        isKnown: isKnown ?? this.isKnown,
        ttl: ttl,
        server: server,
      );

  /// Appends one RTT sample, dropping the oldest beyond [historyLength].
  DiscoveredDevice withRttSample(int ms) {
    final h = [...rttHistory, ms];
    return copyWith(rttHistory: h.length > historyLength ? h.sublist(h.length - historyLength) : h);
  }
}
