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

  static const columns = 'mac, ip, hostname, vendor, model, is_known, first_seen_at, last_seen_at';

  /// Parses a row selected with [columns]; null without a MAC.
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
    );
  }
}
