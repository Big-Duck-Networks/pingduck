import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../domain/agent_platform.dart';
import '../domain/agent_unit.dart';

/// What happened when the app handed an agent its pairing code.
enum PairOutcome {
  paired,

  /// The agent is already paired (to this account or another).
  alreadyPaired,

  /// Supabase said the code was invalid or expired.
  invalidCode,

  /// Another pairing is in progress, or too many attempts.
  busy,

  /// The agent could not reach Supabase.
  upstream,

  /// The agent did not answer.
  unreachable,
}

typedef PairResult = ({PairOutcome outcome, String? agentId});

/// The agent's LAN API (agent/src/agent.cpp): plain HTTP on [agentPort].
/// The token never comes back over it; the agent redeems the code itself.
abstract interface class AgentLanClient {
  Future<FoundAgent?> info(String ip);
  Future<PairResult> pair(String ip, String code);
}

class HttpAgentLanClient implements AgentLanClient {
  HttpAgentLanClient({this.port = agentPort});

  final int port;
  static const _connectTimeout = Duration(seconds: 3);

  /// The agent waits up to 10 s on Supabase before answering a pair.
  static const _pairTimeout = Duration(seconds: 14);

  static const _maxBody = 16 * 1024;

  @override
  Future<FoundAgent?> info(String ip) async {
    try {
      final (status, body) = await _send('GET', ip, '/pingduck/v1/info', timeout: const Duration(seconds: 4));
      if (status != 200) return null;
      return FoundAgent.fromInfo(ip, jsonDecode(body));
    } catch (_) {
      return null;
    }
  }

  @override
  Future<PairResult> pair(String ip, String code) async {
    final int status;
    final String body;
    try {
      (status, body) = await _send('POST', ip, '/pingduck/v1/pair', body: jsonEncode({'code': code}), timeout: _pairTimeout);
    } catch (_) {
      return (outcome: PairOutcome.unreachable, agentId: null);
    }
    Object? error, agentId;
    try {
      final json = jsonDecode(body);
      if (json is Map) (error, agentId) = (json['error'], json['agent_id']);
    } catch (_) {}
    final outcome = switch ((status, error)) {
      (200, _) => PairOutcome.paired,
      (409, _) => PairOutcome.alreadyPaired,
      (400, 'invalid_code') => PairOutcome.invalidCode,
      (429, _) => PairOutcome.busy,
      (502, _) => PairOutcome.upstream,
      _ => PairOutcome.unreachable,
    };
    return (outcome: outcome, agentId: agentId is String ? agentId : null);
  }

  Future<(int, String)> _send(String method, String ip, String path, {String? body, required Duration timeout}) async {
    final client = HttpClient()..connectionTimeout = _connectTimeout;
    try {
      return await () async {
        final req = await client.openUrl(method, Uri(scheme: 'http', host: ip, port: port, path: path));
        req.followRedirects = false;
        if (body != null) {
          req.headers.contentType = ContentType.json;
          req.write(body);
        }
        final res = await req.close();
        final bytes = <int>[];
        await for (final chunk in res) {
          bytes.addAll(chunk);
          if (bytes.length > _maxBody) throw const FormatException('response too large');
        }
        return (res.statusCode, utf8.decode(bytes, allowMalformed: true));
      }().timeout(timeout);
    } finally {
      client.close(force: true);
    }
  }
}

final agentLanClientProvider = Provider<AgentLanClient>((ref) => HttpAgentLanClient());
