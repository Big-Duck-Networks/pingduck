import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/account_auth.dart';
import '../data/agent_repository.dart';
import '../domain/agent_unit.dart';

/// The account's paired agents, or none while anonymous or signed out (an
/// anonymous install can't pair). Invalidate after activating or revoking.
final myAgentsProvider = FutureProvider<List<PairedAgent>>((ref) async {
  final email = ref.watch(accountEmailProvider).value;
  if (email == null) return const [];
  return ref.read(agentRepositoryProvider).myAgents();
});
