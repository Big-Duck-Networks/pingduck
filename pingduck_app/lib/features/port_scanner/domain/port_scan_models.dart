import 'dart:convert';
import '../../device_details/application/diagnostics_controller.dart';

/// Preset or custom port ranges for scanning.
enum PortScanProfile {
  quick('Quick (18)', 'Common critical services (HTTP, SSH, SMB, RTSP, RDP)'),
  standard('Standard (100)', 'Most frequent services and server daemon ports'),
  deep('Deep (1–1024)', 'Full reserved and well-known port range'),
  custom('Custom', 'User-specified comma-separated list of ports');

  const PortScanProfile(this.label, this.description);
  final String label;
  final String description;
}

/// Standard top 100 well-known and service ports.
const standardTop100Ports = [
  20, 21, 22, 23, 25, 53, 67, 68, 69, 80,
  110, 111, 119, 123, 135, 137, 138, 139, 143, 161,
  162, 179, 194, 389, 443, 445, 465, 500, 514, 515,
  520, 554, 587, 631, 636, 873, 902, 989, 990, 993,
  995, 1025, 1080, 1194, 1433, 1434, 1521, 1701, 1723, 1883,
  1900, 2049, 2082, 2083, 2086, 2087, 2181, 2222, 3000, 3128,
  3306, 3389, 4443, 5000, 5060, 5222, 5353, 5432, 5672, 5900,
  5985, 5986, 6379, 6667, 7000, 7001, 8000, 8008, 8080, 8081,
  8088, 8123, 8443, 8888, 9000, 9090, 9092, 9100, 9200, 9418,
  9999, 10000, 27017, 27018, 50000, 50070
];

/// Extra known ports not present in [commonPorts] for rich descriptions.
const extraKnownPorts = [
  PortInfo(20, 'FTP-Data', risk: 'Plaintext data channel'),
  PortInfo(25, 'SMTP', risk: 'Mail server; check authentication'),
  PortInfo(67, 'DHCP Server'),
  PortInfo(68, 'DHCP Client'),
  PortInfo(110, 'POP3', risk: 'Plaintext mail retrieval'),
  PortInfo(123, 'NTP'),
  PortInfo(135, 'RPC Endpoint', risk: 'Windows RPC; often targeted by exploits'),
  PortInfo(143, 'IMAP', risk: 'Plaintext mail access'),
  PortInfo(161, 'SNMP', risk: 'Check for default public community strings'),
  PortInfo(465, 'SMTPS'),
  PortInfo(587, 'Submission (SMTP)'),
  PortInfo(993, 'IMAPS'),
  PortInfo(995, 'POP3S'),
  PortInfo(1194, 'OpenVPN'),
  PortInfo(1433, 'MS-SQL', risk: 'Database server exposed'),
  PortInfo(1521, 'Oracle DB', risk: 'Database server exposed'),
  PortInfo(2049, 'NFS', risk: 'Network filesystem; ensure host access controls'),
  PortInfo(3000, 'Node/Dev Web'),
  PortInfo(3306, 'MySQL', risk: 'Database server exposed'),
  PortInfo(5432, 'PostgreSQL', risk: 'Database server exposed'),
  PortInfo(5672, 'RabbitMQ'),
  PortInfo(6379, 'Redis', risk: 'Often unauthenticated by default'),
  PortInfo(8000, 'HTTP-Dev'),
  PortInfo(8123, 'Home Assistant'),
  PortInfo(8888, 'Jupyter/Admin'),
  PortInfo(9000, 'SonarQube / Portainer'),
  PortInfo(9200, 'Elasticsearch', risk: 'Ensure cluster authentication is active'),
  PortInfo(27017, 'MongoDB', risk: 'Database server exposed; check auth'),
];

/// Returns metadata and risk annotations for [port].
PortInfo lookupPortDetails(int port) {
  // Check core common ports first
  for (final p in commonPorts) {
    if (p.port == port) return p;
  }
  // Check extra known ports
  for (final p in extraKnownPorts) {
    if (p.port == port) return p;
  }
  return PortInfo(port, 'TCP');
}

/// Normalizes and cleans raw host input (stripping protocol, trailing paths, or ports).
String cleanHostInput(String raw) {
  var s = raw.trim();
  if (s.isEmpty) return '';

  // Strip protocol
  if (s.toLowerCase().startsWith('http://')) {
    s = s.substring(7);
  } else if (s.toLowerCase().startsWith('https://')) {
    s = s.substring(8);
  }

  // Strip path or query
  final slash = s.indexOf('/');
  if (slash != -1) s = s.substring(0, slash);

  // Strip port if formatted as host:port (avoid stripping IPv6 if bracketed)
  if (!s.contains(']') && s.contains(':')) {
    final colon = s.indexOf(':');
    s = s.substring(0, colon);
  }

  return s.trim().toLowerCase();
}

/// A target host previously scanned, persisted in local storage.
class RecentPortScanHost {
  const RecentPortScanHost({
    required this.host,
    this.resolvedIp,
    required this.timestamp,
    required this.openPortsCount,
    required this.scannedPortsCount,
    this.profile = PortScanProfile.quick,
  });

  final String host;
  final String? resolvedIp;
  final DateTime timestamp;
  final int openPortsCount;
  final int scannedPortsCount;
  final PortScanProfile profile;

  Map<String, dynamic> toJson() => {
        'host': host,
        'resolvedIp': resolvedIp,
        'timestamp': timestamp.toIso8601String(),
        'openPortsCount': openPortsCount,
        'scannedPortsCount': scannedPortsCount,
        'profile': profile.name,
      };

  factory RecentPortScanHost.fromJson(Map<String, dynamic> json) {
    return RecentPortScanHost(
      host: json['host'] as String? ?? '',
      resolvedIp: json['resolvedIp'] as String?,
      timestamp: DateTime.tryParse(json['timestamp'] as String? ?? '') ?? DateTime.now(),
      openPortsCount: json['openPortsCount'] as int? ?? 0,
      scannedPortsCount: json['scannedPortsCount'] as int? ?? 0,
      profile: PortScanProfile.values.firstWhere(
        (p) => p.name == json['profile'],
        orElse: () => PortScanProfile.quick,
      ),
    );
  }

  static List<RecentPortScanHost> decodeList(String? jsonString) {
    if (jsonString == null || jsonString.isEmpty) return const [];
    try {
      final decoded = jsonDecode(jsonString);
      if (decoded is List) {
        return decoded
            .whereType<Map<String, dynamic>>()
            .map(RecentPortScanHost.fromJson)
            .where((h) => h.host.isNotEmpty)
            .toList();
      }
    } catch (_) {}
    return const [];
  }

  static String encodeList(List<RecentPortScanHost> list) =>
      jsonEncode(list.map((h) => h.toJson()).toList());
}
