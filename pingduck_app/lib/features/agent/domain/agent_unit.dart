/// An agent that answered on the LAN (`GET /pingduck/v1/info`).
class FoundAgent {
  const FoundAgent({
    required this.ip,
    required this.instanceId,
    required this.name,
    required this.version,
    required this.paired,
    this.agentId,
  });

  final String ip;
  final String instanceId;
  final String name;
  final String version;
  final bool paired;

  /// The `agents.id` it is paired as; null while unpaired.
  final String? agentId;

  /// Parses the agent's info JSON; null if it isn't a PingDuck agent we
  /// understand.
  static FoundAgent? fromInfo(String ip, Object? json) {
    if (json is! Map || json['app'] != 'pingduck-agent' || json['api'] != 1) return null;
    final instanceId = json['instance_id'], name = json['name'], version = json['version'];
    if (instanceId is! String || instanceId.isEmpty || name is! String || version is! String) return null;
    final agentId = json['agent_id'];
    return FoundAgent(
      ip: ip,
      instanceId: instanceId,
      name: name.isEmpty ? 'PingDuck agent' : name,
      version: version,
      paired: json['paired'] == true,
      agentId: agentId is String ? agentId : null,
    );
  }
}

/// What the person can do with a found agent.
enum AgentAvailability {
  /// Unpaired: tap to activate.
  available,

  /// Already paired to this account.
  yours,

  /// Paired to someone else's account.
  taken,
}

/// A row of `public.agents` the signed-in user owns (RLS: agents_own).
class PairedAgent {
  const PairedAgent({
    required this.id,
    required this.networkId,
    required this.name,
    this.version,
    this.lastSeenAt,
    required this.createdAt,
  });

  final String id;
  final String networkId;
  final String name;
  final String? version;
  final DateTime? lastSeenAt;
  final DateTime createdAt;

  /// The agent checks in every minute; allow for a couple of missed beats.
  static const onlineWindow = Duration(minutes: 3);

  bool isOnline(DateTime now) => lastSeenAt != null && now.difference(lastSeenAt!) < onlineWindow;

  factory PairedAgent.fromRow(Map<String, dynamic> row) => PairedAgent(
    id: row['id'] as String,
    networkId: row['network_id'] as String,
    name: row['name'] as String,
    version: row['version'] as String?,
    lastSeenAt: DateTime.tryParse(row['last_seen_at'] as String? ?? ''),
    createdAt: DateTime.parse(row['created_at'] as String),
  );
}
