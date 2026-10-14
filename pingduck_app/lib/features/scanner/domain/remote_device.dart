/// A row of Supabase `public.devices`, written by the homelab agent through
/// `agent_sync` and keyed there by MAC.
class RemoteDevice {
  const RemoteDevice({
    required this.mac,
    this.ip,
    this.hostname,
    this.vendor,
    this.model,
    this.isKnown = false,
    this.firstSeenAt,
    this.lastSeenAt,
    this.services = const [],
    this.ttl,
    this.server,
  });

  final String mac;

  /// Without a port or prefix ("10.42.0.5"), as the cache stores it.
  final String? ip;
  final String? hostname;
  final String? vendor;
  final String? model;
  final bool isKnown;
  final DateTime? firstSeenAt;
  final DateTime? lastSeenAt;
  final List<String> services;
  final int? ttl;
  final String? server;

  /// Every column: an app built for a newer schema must not break sync
  /// against a database that has not been migrated yet, or the reverse.
  static const columns = '*';

  /// Parses a `devices` row; null without a MAC. Unknown columns are ignored.
  static RemoteDevice? fromRow(Map<String, dynamic> r) {
    final mac = r['mac'];
    if (mac is! String || mac.isEmpty) return null;
    final ip = r['ip'];
    return RemoteDevice(
      mac: mac,
      // inet comes back as "10.42.0.5" or, from some writers, "10.42.0.5/32".
      ip: ip is String && ip.isNotEmpty ? ip.split('/').first : null,
      hostname: r['hostname'] as String?,
      vendor: r['vendor'] as String?,
      model: r['model'] as String?,
      isKnown: r['is_known'] == true,
      firstSeenAt: DateTime.tryParse(r['first_seen_at'] as String? ?? '')?.toLocal(),
      lastSeenAt: DateTime.tryParse(r['last_seen_at'] as String? ?? '')?.toLocal(),
      services: switch (r['services']) {
        final String s when s.isNotEmpty => s.split(','),
        _ => const [],
      },
      ttl: (r['ttl'] as num?)?.toInt(),
      server: r['server'] as String?,
    );
  }
}
