import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/agent/application/agent_pairing_controller.dart';
import 'package:pingduck_app/features/agent/data/agent_lan_client.dart';
import 'package:pingduck_app/features/agent/data/agent_repository.dart';
import 'package:pingduck_app/features/agent/domain/agent_unit.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/services/local_storage.dart';

import 'fakes.dart';

void main() {
  late FakeBridge bridge;
  late FakeLock lock;
  late FakeAgentRepository repo;
  late FakeAgentLan lanClient;
  late LocalStore store;
  late ProviderContainer container;
  late ProviderSubscription<AgentPairingState> keepAlive;

  setUp(() async {
    AgentPairingController.pollEvery = Duration.zero;
    AgentPairingController.manualPollEvery = const Duration(milliseconds: 10);
    bridge = FakeBridge();
    lock = FakeLock();
    repo = FakeAgentRepository();
    lanClient = FakeAgentLan(repo);
    store = memoryStore();
    container = ProviderContainer(
      overrides: [
        scannerBridgeProvider.overrideWithValue(bridge),
        multicastLockProvider.overrideWithValue(lock),
        scanQuotaProvider.overrideWithValue(FakeQuota()),
        localStoreProvider.overrideWithValue(store),
        agentRepositoryProvider.overrideWithValue(repo),
        agentLanClientProvider.overrideWithValue(lanClient),
      ],
    );
    keepAlive = container.listen(agentPairingProvider, (_, _) {});
    // A finished scan gives the controller its network.
    final running = container.read(scanControllerProvider.notifier).scan();
    await pumpEventQueue();
    await bridge.finish();
    await running;
  });
  tearDown(() async {
    keepAlive.close();
    container.dispose();
    await store.close();
  });

  AgentPairingController ctrl() => container.read(agentPairingProvider.notifier);
  AgentPairingState state() => container.read(agentPairingProvider);

  void onLan(FoundAgent a) {
    lanClient.agents[a.ip] = a;
    bridge.agents.add(dev(a.ip, vendor: 'PingDuck', services: const ['upnp:PingDuckAgent']));
  }

  test('search lists agents as available, yours and taken, without registering anything', () async {
    repo.agents.add(PairedAgent(id: 'mine-1', networkId: 'net-x', name: 'nas', createdAt: DateTime(2026)));
    onLan(agentAt('10.42.0.50', name: 'nas', paired: true, agentId: 'mine-1'));
    onLan(agentAt('10.42.0.51', name: 'neighbour', paired: true, agentId: 'someone-else'));
    onLan(agentAt('10.42.0.52', name: 'pi'));

    await ctrl().search();

    final found = (state() as PairingFound).agents;
    expect([for (final (a, s) in found) (a.name, s)], [
      ('pi', AgentAvailability.available),
      ('nas', AgentAvailability.yours),
      ('neighbour', AgentAvailability.taken),
    ]);
    expect(repo.registrations, 0, reason: 'nothing leaves the phone before Activate');
    expect(lock.held, 0, reason: 'multicast lock released');
    expect(bridge.agentSearches, 1);
  });

  test('a duplicate answer for one agent is listed once', () async {
    onLan(agentAt('10.42.0.52', name: 'pi'));
    bridge.agents.add(bridge.agents.first);
    await ctrl().search();
    expect((state() as PairingFound).agents, hasLength(1));
  });

  test('nothing on the LAN means none found', () async {
    await ctrl().search();
    expect(state(), isA<PairingNoneFound>());
  });

  test('announced over SSDP but not answering on its port is unreachable, not none found', () async {
    bridge.agents.add(dev('10.42.0.170', vendor: 'PingDuck', services: const ['upnp:PingDuckAgent']));
    await ctrl().search();
    expect((state() as PairingUnreachable).ips, ['10.42.0.170']);
  });

  test('reachable agents are listed and the unreachable ones noted', () async {
    onLan(agentAt('10.42.0.52', name: 'pi'));
    bridge.agents.add(dev('10.42.0.170', vendor: 'PingDuck', services: const ['upnp:PingDuckAgent']));
    await ctrl().search();
    final found = state() as PairingFound;
    expect(found.agents.single.$1.name, 'pi');
    expect(found.unreachable, ['10.42.0.170']);
  });

  test('off the LAN is its own failure', () async {
    bridge.lan = null;
    await ctrl().search();
    expect((state() as PairingFailed).failure, PairingFailure.notOnLan);
  });

  test('activate registers the network, hands over a code and confirms', () async {
    final pi = agentAt('10.42.0.52', name: 'pi');
    onLan(pi);
    await ctrl().search();
    await ctrl().activate(pi);

    final done = state() as PairingActivated;
    expect(done.agent.name, 'pi');
    expect(done.networkLabel, 'CyberLab_5G');
    expect(repo.registrations, 1);
    expect(lanClient.pairCalls.single.$1, '10.42.0.52');
  });

  test('no monitoring left on the plan', () async {
    repo.slots = 0;
    final pi = agentAt('10.42.0.52');
    onLan(pi);
    await ctrl().activate(pi);
    expect((state() as PairingFailed).failure, PairingFailure.planRequired);
    expect(lanClient.pairCalls, isEmpty);
  });

  test('an agent paired meanwhile by someone else', () async {
    final pi = agentAt('10.42.0.52');
    onLan(pi);
    lanClient.forceOutcome = PairOutcome.alreadyPaired;
    await ctrl().activate(pi);
    expect((state() as PairingFailed).failure, PairingFailure.takenByOther);
  });

  test('a rejected code is retried once with a fresh one', () async {
    final pi = agentAt('10.42.0.52');
    onLan(pi);
    lanClient.forceOutcome = PairOutcome.invalidCode;
    await ctrl().activate(pi);
    expect(lanClient.pairCalls, hasLength(2));
    expect(lanClient.pairCalls[0].$2, isNot(lanClient.pairCalls[1].$2));
    expect((state() as PairingFailed).failure, PairingFailure.codeRejected);
  });

  test('agent gone, or agent without internet', () async {
    final pi = agentAt('10.42.0.52');
    onLan(pi);
    lanClient.forceOutcome = PairOutcome.unreachable;
    await ctrl().activate(pi);
    expect((state() as PairingFailed).failure, PairingFailure.agentUnreachable);
    lanClient.forceOutcome = PairOutcome.upstream;
    await ctrl().activate(pi);
    expect((state() as PairingFailed).failure, PairingFailure.agentOffline);
  });

  test('server down before the code', () async {
    final pi = agentAt('10.42.0.52');
    onLan(pi);
    repo.offline = true;
    await ctrl().activate(pi);
    expect((state() as PairingFailed).failure, PairingFailure.serverUnreachable);
  });

  test('manual code waits for the agent to redeem it', () async {
    await ctrl().startManualCode();
    final shown = state() as PairingManualCode;
    expect(shown.code, hasLength(8));
    expect(shown.expired, isFalse);

    repo.redeem(shown.code, 'vlan-box');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect((state() as PairingActivated).agent.name, 'vlan-box');
  });
}
