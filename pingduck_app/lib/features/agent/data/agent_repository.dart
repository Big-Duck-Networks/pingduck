import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/ffi/scanner_bridge.dart';
import '../../../services/local_storage.dart';
import '../../auth/session.dart';
import '../../scanner/application/scan_controller.dart';
import '../domain/agent_platform.dart';
import '../domain/agent_unit.dart';

/// The plan has no monitored networks left (Free, or every slot in use).
class PlanLimitException implements Exception {
  const PlanLimitException();
}

/// The request needs an email account; this install is anonymous.
class AccountRequiredException implements Exception {
  const AccountRequiredException();
}

/// Too many instruction emails in the last hour.
class RateLimitedException implements Exception {
  const RateLimitedException();
}

typedef PairingCode = ({String code, DateTime expiresAt});

/// The server side of monitoring units: networks, pairing codes and agents
/// (supabase/migrations/20261006120000_initial_schema.sql and
/// 20261010120000_agent_pairing.sql).
abstract interface class AgentRepository {
  /// How many networks the plan may monitor; 0 on Free.
  Future<int> maxMonitoredNetworks();

  /// The Supabase id of the network the phone is on, creating the row the
  /// first time. This is the only place the subnet, gateway and Wi-Fi name
  /// leave the phone, and only when the person adds a monitoring unit.
  Future<String> ensureRemoteNetwork(int localNetworkId, LanInfo lan);

  /// A 10-minute single-use code for [networkId]. Throws [PlanLimitException].
  Future<PairingCode> createCode(String networkId);

  /// The account's live agents, newest first.
  Future<List<PairedAgent>> myAgents();

  Future<void> revoke(String agentId);

  /// Emails the install steps to the account's address and returns it.
  Future<String> emailInstructions(AgentPlatform platform);
}

class SupabaseAgentRepository implements AgentRepository {
  SupabaseAgentRepository(this._store);

  final LocalStore _store;

  @override
  Future<int> maxMonitoredNetworks() async {
    final plan = await (await signedInClient()).rpc('my_plan');
    final row = plan is List ? (plan.isEmpty ? null : plan.first) : plan;
    return ((row as Map?)?['max_monitored_networks'] as num?)?.toInt() ?? 0;
  }

  @override
  Future<String> ensureRemoteNetwork(int localNetworkId, LanInfo lan) async {
    final db = await signedInClient();
    final saved = await _store.remoteIdOf(localNetworkId);
    if (saved != null) {
      final row = await db.from('networks').select('id').eq('id', saved).maybeSingle();
      if (row != null) return saved;
    }
    var query = db.from('networks').select('id').eq('cidr', lan.cidr);
    query = lan.gateway == null ? query.isFilter('gateway_ip', null) : query.eq('gateway_ip', lan.gateway!);
    final existing = await query.limit(1).maybeSingle();
    final id = existing != null
        ? existing['id'] as String
        : (await db
                  .from('networks')
                  .insert({'cidr': lan.cidr, 'gateway_ip': lan.gateway, 'ssid': lan.ssid, 'name': lan.ssid})
                  .select('id')
                  .single())['id']
              as String;
    await _store.setRemoteId(localNetworkId, id);
    return id;
  }

  @override
  Future<PairingCode> createCode(String networkId) async {
    try {
      final r = await (await signedInClient()).rpc('create_pairing_code', params: {'p_network_id': networkId});
      return (code: r['code'] as String, expiresAt: DateTime.parse(r['expires_at'] as String));
    } on PostgrestException catch (e) {
      if (e.message.startsWith('plan_limit')) throw const PlanLimitException();
      rethrow;
    }
  }

  @override
  Future<List<PairedAgent>> myAgents() async {
    final rows = await (await signedInClient())
        .from('agents')
        .select('id, network_id, name, version, last_seen_at, created_at')
        .isFilter('revoked_at', null)
        .order('created_at', ascending: false);
    return [for (final r in rows) PairedAgent.fromRow(r)];
  }

  @override
  Future<void> revoke(String agentId) async =>
      (await signedInClient()).rpc('revoke_agent', params: {'p_agent_id': agentId});

  @override
  Future<String> emailInstructions(AgentPlatform platform) async {
    try {
      final r = await (await signedInClient()).rpc(
        'email_agent_instructions',
        params: {'p_platform': platform.serverValue},
      );
      return r['sent_to'] as String;
    } on PostgrestException catch (e) {
      if (e.message.startsWith('account_required')) throw const AccountRequiredException();
      if (e.message.startsWith('rate_limited')) throw const RateLimitedException();
      rethrow;
    }
  }
}

final agentRepositoryProvider = Provider<AgentRepository>(
  (ref) => SupabaseAgentRepository(ref.read(localStoreProvider)),
);
