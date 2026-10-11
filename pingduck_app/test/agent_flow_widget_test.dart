import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/desktop/desktop.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/agent/application/agent_pairing_controller.dart';
import 'package:pingduck_app/features/agent/application/agent_status.dart';
import 'package:pingduck_app/features/agent/data/agent_lan_client.dart';
import 'package:pingduck_app/features/agent/data/agent_repository.dart';
import 'package:pingduck_app/features/agent/domain/agent_platform.dart';
import 'package:pingduck_app/features/agent/domain/agent_unit.dart';
import 'package:pingduck_app/features/agent/presentation/add_unit_intro_screen.dart';
import 'package:pingduck_app/features/agent/presentation/agent_screen.dart';
import 'package:pingduck_app/features/agent/presentation/this_pc_panel.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/auth/sign_in_screen.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';

import 'fakes.dart';

void main() {
  late FakeBridge bridge;
  late FakeAuth auth;
  late FakeAgentRepository repo;
  late FakeAgentLan lanClient;

  setUp(() {
    AgentPairingController.pollEvery = Duration.zero;
    AgentPairingController.manualPollEvery = const Duration(milliseconds: 20);
  });

  /// A screen with one button that opens the flow, like the Account tab.
  Future<void> pumpFlow(WidgetTester tester, {bool signedIn = true, Widget? home}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.5;
    addTearDown(tester.view.reset);
    bridge = FakeBridge();
    auth = FakeAuth(accounts: {'me@example.com': 'pw'});
    if (signedIn) await auth.signIn('me@example.com', 'pw');
    repo = FakeAgentRepository();
    lanClient = FakeAgentLan(repo);
    final store = memoryStore();
    addTearDown(store.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scannerBridgeProvider.overrideWithValue(bridge),
          multicastLockProvider.overrideWithValue(FakeLock()),
          scanQuotaProvider.overrideWithValue(FakeQuota()),
          localStoreProvider.overrideWithValue(store),
          restoredScanProvider.overrideWithValue(
            const ScanState(lan: testLan, networkId: 1, networkName: 'CyberLab_5G'),
          ),
          accountAuthProvider.overrideWithValue(auth),
          agentRepositoryProvider.overrideWithValue(repo),
          agentLanClientProvider.overrideWithValue(lanClient),
          startWithWindowsProvider.overrideWith((ref) async => false),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: Scaffold(
            body:
                home ??
                Builder(
                  builder: (context) => Center(
                    child: TextButton(onPressed: () => openAddMonitoringUnit(context), child: const Text('open')),
                  ),
                ),
          ),
        ),
      ),
    );
    if (home == null) {
      await tester.tap(find.text('open'));
    }
    await tester.pumpAndSettle();
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.tap(find.text(text));
    await tester.pumpAndSettle();
  }

  void onLan(FoundAgent a) {
    lanClient.agents[a.ip] = a;
    bridge.agents.add(dev(a.ip, vendor: 'PingDuck', services: const ['upnp:PingDuckAgent']));
  }

  testWidgets('intro lists only what the agent really does', (tester) async {
    await pumpFlow(tester);
    expect(find.text('Watch your network around the clock'), findsOneWidget);
    expect(find.textContaining('MAC address'), findsOneWidget);
    expect(find.textContaining('Block'), findsNothing);
    await tapText(tester, 'MAYBE LATER');
    expect(find.text('open'), findsOneWidget);
  });

  testWidgets('anonymous installs sign in first', (tester) async {
    await pumpFlow(tester, signedIn: false);
    await tapText(tester, 'LET\'S START');
    expect(find.byType(SignInScreen), findsOneWidget);
  });

  testWidgets('Free shows Premium required', (tester) async {
    await pumpFlow(tester);
    repo.slots = 0;
    await tapText(tester, 'LET\'S START');
    expect(find.text('Monitoring is a Premium feature'), findsOneWidget);
  });

  testWidgets('platform picks the steps, which copy and email', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'LET\'S START');
    expect(find.text('Where will PingDuck watch from?'), findsOneWidget);
    expect(find.text('PINGDUCK DESKTOP'), findsOneWidget);
    expect(find.text('PINGDUCK AGENT'), findsOneWidget);
    expect(find.text('macOS'), findsNothing, reason: 'only platforms that exist');

    // Windows is first and preselected, with Fing's four steps.
    await tapText(tester, 'NEXT');
    expect(find.text('Get PingDuck on Windows'), findsOneWidget);
    expect(find.text('Type pingduck.app/agent in your browser'), findsOneWidget);
    expect(find.text('Sign in to get your data in sync'), findsOneWidget);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    await tapText(tester, 'Raspberry Pi');
    await tapText(tester, 'NEXT');
    expect(find.text('Install the agent on Raspberry Pi'), findsOneWidget);
    expect(find.text('curl -fsSL https://get.docker.com | sh'), findsOneWidget);

    String? copied;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') copied = (call.arguments as Map)['text'] as String;
      return null;
    });
    await tester.tap(find.byTooltip('Copy command').first);
    await tester.pump();
    expect(copied, 'curl -fsSL https://get.docker.com | sh');

    await tapText(tester, 'EMAIL ME THESE STEPS');
    expect(repo.emails, [AgentPlatform.raspberryPi]);
    expect(find.text('Sent to me@example.com'), findsOneWidget);
  });

  testWidgets('find my agent, activate, done', (tester) async {
    await pumpFlow(tester);
    onLan(agentAt('10.42.0.170', name: 'pingduck-vm'));
    onLan(agentAt('10.42.0.171', name: 'neighbour', paired: true, agentId: 'not-mine'));
    await tapText(tester, 'LET\'S START');
    await tapText(tester, 'NEXT');
    await tapText(tester, 'FIND MY AGENT');

    expect(find.text('Found 2 agents'), findsOneWidget);
    expect(find.text('AVAILABLE'), findsOneWidget);
    expect(find.text('TAKEN'), findsOneWidget);
    expect(find.textContaining('ACTIVATE'), findsNothing);

    await tapText(tester, 'neighbour');
    expect(find.textContaining('ACTIVATE'), findsNothing, reason: 'a taken agent cannot be chosen');

    await tapText(tester, 'pingduck-vm');
    await tapText(tester, 'ACTIVATE PINGDUCK-VM');
    expect(find.text('pingduck-vm is on watch'), findsOneWidget);
    expect(find.text('CyberLab_5G'), findsOneWidget);
    expect(repo.agents.single.name, 'pingduck-vm');
  });

  testWidgets('nothing found offers a pairing code', (tester) async {
    await pumpFlow(tester);
    await tapText(tester, 'LET\'S START');
    await tapText(tester, 'NEXT');
    await tapText(tester, 'FIND MY AGENT');
    expect(find.text('No agent found'), findsOneWidget);
    expect(find.text('--net=host', findRichText: true), findsNothing);
    expect(find.textContaining('host networking', findRichText: true), findsOneWidget);

    // The code screen ticks every second, so it never settles.
    await tester.ensureVisible(find.text('USE A PAIRING CODE'));
    await tester.tap(find.text('USE A PAIRING CODE'));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Pair with a code'), findsOneWidget);
    final code = repo.codes.keys.single;
    expect(find.text('${code.substring(0, 4)} ${code.substring(4)}'), findsOneWidget);
    expect(find.textContaining('PINGDUCK_PAIRING_CODE=$code'), findsOneWidget);

    repo.redeem(code, 'vlan-box');
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    await tester.pumpAndSettle();
    expect(find.text('vlan-box is on watch'), findsOneWidget);
  });

  testWidgets('an agent that announces but can\'t be reached names the likely blocks', (tester) async {
    await pumpFlow(tester);
    bridge.agents.add(dev('10.42.0.170', vendor: 'PingDuck', services: const ['upnp:PingDuckAgent']));
    await tapText(tester, 'LET\'S START');
    await tapText(tester, 'NEXT');
    await tapText(tester, 'FIND MY AGENT');
    expect(find.text('Found an agent, but can\'t connect'), findsOneWidget);
    expect(find.textContaining('10.42.0.170'), findsOneWidget);
    expect(find.textContaining('libvirt network filters'), findsOneWidget);
    expect(find.text('USE A PAIRING CODE'), findsOneWidget);
  });

  testWidgets('This PC pairs its own agent service in one click', (tester) async {
    debugDesktopOverride = true;
    addTearDown(() => debugDesktopOverride = null);
    await pumpFlow(tester, home: const SingleChildScrollView(child: ThisPcPanel()));
    expect(find.text('NOT RUNNING'), findsOneWidget, reason: 'no service answering on 127.0.0.1');

    lanClient.agents['127.0.0.1'] = agentAt('127.0.0.1', name: 'WEBCAP-717');
    final container = ProviderScope.containerOf(tester.element(find.byType(ThisPcPanel)));
    container.invalidate(localAgentProvider);
    await tester.pumpAndSettle();
    expect(find.text('NOT MONITORING'), findsOneWidget);

    await tapText(tester, 'MONITOR THIS NETWORK');
    expect(repo.agents.single.name, 'WEBCAP-717');
    expect(lanClient.pairCalls.single.$1, '127.0.0.1');
    expect(find.text('MONITORING'), findsOneWidget);
    expect(find.text('This PC is now monitoring CyberLab_5G'), findsOneWidget);
  });

  testWidgets('Homelab Agent shows paired agents and revokes', (tester) async {
    await pumpFlow(tester, home: const AgentScreen());
    expect(find.text('No agent paired'), findsOneWidget);
    expect(find.text('ADD MONITORING UNIT'), findsOneWidget);

    repo.agents.add(
      PairedAgent(
        id: 'a1',
        networkId: 'n1',
        name: 'pingduck-vm',
        version: '0.9.0',
        lastSeenAt: DateTime.now(),
        createdAt: DateTime(2026, 10, 10),
      ),
    );
    final container = ProviderScope.containerOf(tester.element(find.byType(AgentScreen)));
    container.invalidate(myAgentsProvider);
    await tester.pumpAndSettle();
    expect(find.text('pingduck-vm'), findsOneWidget);
    expect(find.text('ONLINE'), findsOneWidget);
    expect(find.text('just now'), findsOneWidget);

    await tapText(tester, 'REVOKE');
    expect(find.text('REVOKE AGENT?'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'REVOKE'));
    await tester.pumpAndSettle();
    expect(repo.revoked, ['a1']);
    expect(find.text('No agent paired'), findsOneWidget);
  });
}
