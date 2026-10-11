import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../scanner/application/scan_controller.dart';
import '../data/agent_lan_client.dart';
import '../data/agent_repository.dart';
import '../domain/agent_unit.dart';
import 'agent_status.dart';

enum PairingFailure {
  notOnLan('Connect to the Wi-Fi the agent is on, then search again.'),
  planRequired('Monitoring needs Premium. Your plan has no free monitored networks.'),
  takenByOther('That agent is paired to another account. Revoke it there, or wipe the agent\'s volume.'),
  agentUnreachable('The agent stopped answering. Check it is still running, then try again.'),
  agentOffline('The agent couldn\'t reach PingDuck\'s servers. Check the box has internet access.'),
  serverUnreachable('Couldn\'t reach PingDuck\'s servers. Check your connection and try again.'),
  codeRejected('The agent didn\'t accept the code. Try again.'),
  notConfirmed('The agent took the code but hasn\'t checked in yet. Give it a minute, then look on the Homelab Agent screen.');

  const PairingFailure(this.message);
  final String message;
}

enum ActivationStep { registering, sending, confirming }

sealed class AgentPairingState {
  const AgentPairingState();
}

class PairingSearching extends AgentPairingState {
  const PairingSearching();
}

class PairingFound extends AgentPairingState {
  const PairingFound(this.agents, {this.unreachable = const []});
  final List<(FoundAgent, AgentAvailability)> agents;

  /// IPs that announced an agent over SSDP but didn't answer on its port.
  final List<String> unreachable;
}

/// Agents announced themselves, but none answered on the agent's port (44480): SSDP got
/// through and TCP didn't, which points at a firewall or a VM network filter.
class PairingUnreachable extends AgentPairingState {
  const PairingUnreachable(this.ips);
  final List<String> ips;
}

class PairingNoneFound extends AgentPairingState {
  const PairingNoneFound();
}

class PairingActivating extends AgentPairingState {
  const PairingActivating(this.agent, this.step);
  final FoundAgent agent;
  final ActivationStep step;
}

class PairingManualCode extends AgentPairingState {
  const PairingManualCode(this.code, this.expiresAt, {this.expired = false});
  final String code;
  final DateTime expiresAt;
  final bool expired;
}

class PairingActivated extends AgentPairingState {
  const PairingActivated(this.agent, this.networkLabel);
  final PairedAgent agent;
  final String networkLabel;
}

class PairingFailed extends AgentPairingState {
  const PairingFailed(this.failure);
  final PairingFailure failure;
}

/// Finds agents on the LAN and activates one: register the network, get a
/// code, hand it to the agent, wait for it to show up in `agents`.
class AgentPairingController extends Notifier<AgentPairingState> {
  /// How long to wait for a paired agent to appear in `agents`.
  static const confirmTimeout = Duration(seconds: 10);
  static Duration pollEvery = const Duration(seconds: 1);
  static Duration manualPollEvery = const Duration(seconds: 3);

  Timer? _manualTimer;
  int _run = 0;

  AgentRepository get _repo => ref.read(agentRepositoryProvider);
  AgentLanClient get _lan => ref.read(agentLanClientProvider);

  @override
  AgentPairingState build() {
    ref.onDispose(() => _manualTimer?.cancel());
    return const PairingSearching();
  }

  bool _current(int run) => ref.mounted && run == _run;

  Future<void> search() async {
    final run = ++_run;
    _manualTimer?.cancel();
    state = const PairingSearching();
    final bridge = ref.read(scannerBridgeProvider);
    if (await bridge.lanInfo() == null) {
      if (_current(run)) state = const PairingFailed(PairingFailure.notOnLan);
      return;
    }

    final lock = ref.read(multicastLockProvider);
    var lockHeld = false;
    final ips = <String>{};
    try {
      try {
        await lock.acquire();
        lockHeld = true;
      } catch (_) {}
      await for (final d in bridge.findAgents()) {
        ips.add(d.ip);
      }
    } catch (_) {
      // Discovery failed outright; treat it like finding nothing.
    } finally {
      if (lockHeld) await lock.release().catchError((_) {});
    }
    if (!_current(run)) return;

    final order = ips.toList();
    final infos = await Future.wait(order.map(_lan.info));
    final byInstance = <String, FoundAgent>{
      for (final a in infos.whereType<FoundAgent>()) a.instanceId: a,
    };
    final unreachable = [
      for (var i = 0; i < order.length; i++)
        if (infos[i] == null) order[i],
    ];
    if (byInstance.isEmpty) {
      if (_current(run)) state = unreachable.isEmpty ? const PairingNoneFound() : PairingUnreachable(unreachable);
      return;
    }

    var mine = <String>{};
    if (byInstance.values.any((a) => a.paired)) {
      try {
        mine = {for (final a in await _repo.myAgents()) a.id};
      } catch (_) {}
    }
    if (!_current(run)) return;
    final list = [
      for (final a in byInstance.values)
        (
          a,
          !a.paired
              ? AgentAvailability.available
              : mine.contains(a.agentId)
              ? AgentAvailability.yours
              : AgentAvailability.taken,
        ),
    ]..sort((x, y) => x.$2.index.compareTo(y.$2.index));
    state = PairingFound(list, unreachable: unreachable);
  }

  Future<void> activate(FoundAgent agent) async {
    final run = ++_run;
    _manualTimer?.cancel();
    state = PairingActivating(agent, ActivationStep.registering);

    final String networkId;
    final PairingCode code;
    try {
      networkId = await _registerNetwork();
      code = await _repo.createCode(networkId);
    } on PlanLimitException {
      if (_current(run)) state = const PairingFailed(PairingFailure.planRequired);
      return;
    } on _NotOnLan {
      if (_current(run)) state = const PairingFailed(PairingFailure.notOnLan);
      return;
    } catch (_) {
      if (_current(run)) state = const PairingFailed(PairingFailure.serverUnreachable);
      return;
    }
    if (!_current(run)) return;

    state = PairingActivating(agent, ActivationStep.sending);
    var result = await _lan.pair(agent.ip, code.code);
    if (result.outcome == PairOutcome.invalidCode) {
      // A code can lapse between minting and redeeming; one fresh try.
      try {
        result = await _lan.pair(agent.ip, (await _repo.createCode(networkId)).code);
      } catch (_) {}
    }
    if (!_current(run)) return;
    final failure = switch (result.outcome) {
      PairOutcome.paired => null,
      PairOutcome.alreadyPaired => PairingFailure.takenByOther,
      PairOutcome.invalidCode || PairOutcome.busy => PairingFailure.codeRejected,
      PairOutcome.upstream => PairingFailure.agentOffline,
      PairOutcome.unreachable => PairingFailure.agentUnreachable,
    };
    if (failure != null) {
      state = PairingFailed(failure);
      return;
    }

    state = PairingActivating(agent, ActivationStep.confirming);
    final agentId = result.agentId;
    final paired = await _waitForAgent((a) => agentId != null ? a.id == agentId : a.networkId == networkId, confirmTimeout);
    if (!_current(run)) return;
    ref.invalidate(myAgentsProvider);
    state = paired == null ? const PairingFailed(PairingFailure.notConfirmed) : PairingActivated(paired, _networkLabel());
  }

  /// The fallback for networks where the phone can't reach the agent: show
  /// a code for PINGDUCK_PAIRING_CODE and wait for the agent to redeem it.
  Future<void> startManualCode() async {
    final run = ++_run;
    _manualTimer?.cancel();
    state = const PairingSearching();
    final String networkId;
    final PairingCode code;
    final Set<String> before;
    try {
      networkId = await _registerNetwork();
      before = {for (final a in await _repo.myAgents()) a.id};
      code = await _repo.createCode(networkId);
    } on PlanLimitException {
      if (_current(run)) state = const PairingFailed(PairingFailure.planRequired);
      return;
    } on _NotOnLan {
      if (_current(run)) state = const PairingFailed(PairingFailure.notOnLan);
      return;
    } catch (_) {
      if (_current(run)) state = const PairingFailed(PairingFailure.serverUnreachable);
      return;
    }
    if (!_current(run)) return;
    state = PairingManualCode(code.code, code.expiresAt);

    var polling = false;
    _manualTimer = Timer.periodic(manualPollEvery, (_) async {
      if (polling || !_current(run)) return;
      if (DateTime.now().isAfter(code.expiresAt)) {
        _manualTimer?.cancel();
        state = PairingManualCode(code.code, code.expiresAt, expired: true);
        return;
      }
      polling = true;
      try {
        final fresh = (await _repo.myAgents()).where((a) => a.networkId == networkId && !before.contains(a.id));
        if (fresh.isNotEmpty && _current(run)) {
          _manualTimer?.cancel();
          ref.invalidate(myAgentsProvider);
          state = PairingActivated(fresh.first, _networkLabel());
        }
      } catch (_) {
        // Try again on the next tick.
      } finally {
        polling = false;
      }
    });
  }

  Future<String> _registerNetwork() async {
    final scan = ref.read(scanControllerProvider);
    final lan = await ref.read(scannerBridgeProvider).lanInfo();
    final localId = scan.networkId;
    if (lan == null || localId == null || scan.lan?.cidr != lan.cidr) throw const _NotOnLan();
    return _repo.ensureRemoteNetwork(localId, lan);
  }

  Future<PairedAgent?> _waitForAgent(bool Function(PairedAgent) match, Duration timeout) async {
    final deadline = DateTime.now().add(timeout);
    while (ref.mounted) {
      try {
        final hit = (await _repo.myAgents()).where(match);
        if (hit.isNotEmpty) return hit.first;
      } catch (_) {}
      if (DateTime.now().isAfter(deadline)) return null;
      await Future<void>.delayed(pollEvery);
    }
    return null;
  }

  String _networkLabel() => ref.read(scanControllerProvider).networkTitle;
}

class _NotOnLan implements Exception {
  const _NotOnLan();
}

final agentPairingProvider = NotifierProvider.autoDispose<AgentPairingController, AgentPairingState>(
  AgentPairingController.new,
);
