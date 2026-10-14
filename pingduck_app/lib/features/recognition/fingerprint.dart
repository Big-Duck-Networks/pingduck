import '../scanner/domain/discovered_device.dart';
import 'recognition_rules.dart';

/// What a kind of device looks like on the network, so a label the user
/// gives one device can be offered for others like it.
///
/// Built only from signals that are the same for every unit of a product:
/// the MAC vendor, the model and services it announces, its SSDP server
/// string without version numbers, its initial TTL and the shape of its
/// hostname. Never the IP, the MAC itself or any word of the hostname that
/// isn't in [hostWords], so it carries no names.
abstract final class Fingerprint {
  /// Null when the device sends too little to tell it apart: a TTL and a
  /// hostname shape alone would match every phone with a private MAC.
  static String? of(DiscoveredDevice d) {
    final vendor = d.hasPrivateMac ? null : _norm(d.vendor);
    final model = d.model == null || d.model!.contains('UPnP/') ? null : _norm(d.model);
    final services = ([for (final s in d.services) s.toLowerCase()]..sort()).join(',');
    final server = d.server == null ? null : _withoutVersions(d.server!);
    if (vendor == null && model == null && services.isEmpty && server == null) return null;
    return [
      'v=${vendor ?? ''}',
      'm=${model ?? ''}',
      's=$services',
      'r=${server ?? ''}',
      't=${_initialTtl(d.ttl) ?? ''}',
      'h=${hostShape(d.hostname) ?? ''}',
    ].join('|');
  }

  /// "Carls-iPhone" → "*-iphone", "ESP_3A1B2C" → "esp_#",
  /// "DESKTOP-4F2K9QZ" → "desktop-*".
  static String? hostShape(String? hostname) {
    if (hostname == null || hostname.trim().isEmpty) return null;
    final host = hostname.trim().toLowerCase().replaceFirst(RegExp(r'\.(local|lan|home|localdomain)\.?$'), '');
    return host.replaceAllMapped(RegExp(r'[a-z0-9]+'), (m) {
      final t = m[0]!;
      if (hostWords.contains(t)) return t;
      if (RegExp(r'^[0-9a-f]+$').hasMatch(t) && RegExp(r'\d').hasMatch(t)) return '#';
      return '*';
    });
  }

  static String? _norm(String? s) {
    final t = s?.trim().toLowerCase();
    return t == null || t.isEmpty ? null : t;
  }

  /// "Linux/5.15.170-android14, UPnP/1.0" → "linux/#, upnp/#".
  static String _withoutVersions(String s) => s.toLowerCase().replaceAll(RegExp(r'\d[\w.\-]*'), '#');

  /// Hosts start at 32, 64, 128 or 255 and every router hop takes one off.
  static int? _initialTtl(int? ttl) {
    if (ttl == null || ttl <= 0) return null;
    for (final start in const [32, 64, 128]) {
      if (ttl <= start) return start;
    }
    return 255;
  }
}
