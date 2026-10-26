import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/scanner/presentation/device_card.dart';
import 'package:pingduck_app/core/theme/pingduck_colors.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/core/constants/app_version.dart';
import 'package:pingduck_app/core/network/lan_connectivity.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/core/widgets/pd_widgets.dart';
import 'package:pingduck_app/features/agent/application/agent_status.dart';
import 'package:pingduck_app/features/agent/domain/agent_unit.dart';
import 'package:pingduck_app/features/topology/presentation/topology_screen.dart';
import 'package:pingduck_app/main.dart';
import 'package:pingduck_app/services/billing.dart';
import 'package:pingduck_app/services/local_storage.dart';

import 'fakes.dart';

void main() {
  late FakeBridge bridge;
  late FakeLan lan;
  late FakeAuth auth;

  late LocalStore currentStore;

  /// Seeds the cache like a previous session did, then restores from it the
  /// way main() does.
  Future<Widget> app(
    WidgetTester tester, {
    required bool onboarded,
    List<DiscoveredDevice> cached = const [],
    bool connected = true,
    Map<String, String> accounts = const {},
    bool isPremium = true,
    bool autoScanOnLaunch = true,
    List<PairedAgent>? agents,
  }) async {
    bridge = FakeBridge();
    auth = FakeAuth(accounts: accounts);
    lan = FakeLan(connected);
    final store = memoryStore();
    currentStore = store;
    addTearDown(store.close);
    final restored = await tester.runAsync(() async {
      await store.setSetting('isPremium', isPremium ? '1' : '0');
      if (!autoScanOnLaunch) {
        await store.setSetting('autoScanOnLaunch', '0');
      }
      if (cached.isNotEmpty) {
        final id = await store.networkFor(key: testLan.key, cidr: testLan.cidr, gateway: testLan.gateway);
        await store.saveDevices(id, cached);
        await store.markScanned(id, DateTime(2026, 10, 5), ssid: testLan.ssid);
        await store.setSetting('lastNetworkId', '$id');
      }
      return restoreLastScan(store);
    });
    return ProviderScope(
      overrides: [
        scannerBridgeProvider.overrideWithValue(bridge),
        multicastLockProvider.overrideWithValue(FakeLock()),
        scanQuotaProvider.overrideWithValue(FakeQuota()),
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(restored!),
        onboardedProvider.overrideWith(() => Onboarded(onboarded)),
        lanConnectivityProvider.overrideWithValue(lan),
        accountAuthProvider.overrideWithValue(auth),
        // The real RevenueCat SDK has no platform side in tests.
        billingProvider.overrideWithValue(FakeBilling()),
        if (agents != null) myAgentsProvider.overrideWith((ref) async => agents),
      ],
      child: const PingDuckApp(),
    );
  }

  /// The ledger sits below the radar, outside the lazily built viewport.
  Future<void> scrollTo(WidgetTester tester, Finder f) => tester.scrollUntilVisible(
    f,
    300,
    scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first,
  );

  /// The Account tab's App settings row sits below the Plan panel, so these
  /// tests use a taller screen instead of scrolling.
  Future<void> showAppSettingsRow(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 3600);
    addTearDown(tester.view.reset);
    await tester.pumpAndSettle();
  }

  Future<void> openAppSettings(WidgetTester tester) async {
    await showAppSettingsRow(tester);
    await tester.tap(find.text('App settings'));
  }

  Future<void> settleScan(WidgetTester tester) async {
    await tester.pump();
    if (bridge.devices != null && !bridge.done!.isCompleted) await bridge.finish();
    await tester.pumpAndSettle();
  }

  testWidgets('first launch shows onboarding, then scans', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: false));
    expect(find.text('START FIRST SCAN'), findsOneWidget);
    expect(bridge.scans, 0);

    await tester.ensureVisible(find.text('START FIRST SCAN'));
    await tester.tap(find.text('START FIRST SCAN'));
    await tester.pump();
    await tester.pump();
    expect(find.text('PINGDUCK'), findsOneWidget);
    expect(bridge.scans, 1);
    await settleScan(tester);
  });

  testWidgets('cached devices show on the first frame, then light up', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final cached = dev('10.42.0.20', hostname: 'Living Room TV', services: ['_googlecast._tcp']);
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [cached]));

    await scrollTo(tester, find.text('Living Room TV'));
    expect(find.text('CyberLab_5G'), findsOneWidget); // remembered from the last scan
    await tester.pump();
    expect(bridge.scans, 1); // returning users get a scan on launch

    bridge.devices!.add(dev('10.42.0.20', rtt: 4));
    await tester.pump();
    expect(find.text('4 ms', findRichText: true), findsWidgets);
    await settleScan(tester);
  });

  testWidgets('Node Inspect shows what the device is and its OS, marking guesses', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final chromecast = DiscoveredDevice(
      ip: '10.42.0.17',
      hostname: 'Chromecast',
      vendor: 'Google, Inc.',
      model: 'Chromecast',
      server: 'Linux/5.15.170-android14-11-gf4a1f03072a, UPnP/1.0',
      ttl: 64,
      sources: const {DiscoverySource.mdns, DiscoverySource.ssdp},
      firstSeen: DateTime(2026, 10, 5),
      lastSeen: DateTime(2026, 10, 5),
    );
    final pc = DiscoveredDevice(
      ip: '10.42.0.100',
      vendor: 'LCFC(Hefei) Electronics Technology co., ltd',
      ttl: 128,
      sources: const {DiscoverySource.icmp},
      firstSeen: DateTime(2026, 10, 5),
      lastSeen: DateTime(2026, 10, 5),
    );
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [chromecast, pc]));
    await settleScan(tester);

    await scrollTo(tester, find.text('Chromecast'));
    await tester.tap(find.text('Chromecast').first);
    await tester.pumpAndSettle();
    expect(find.text('DEVICE'), findsOneWidget);
    expect(find.text('OPERATING SYSTEM'), findsOneWidget);
    expect(find.text('Android 14'), findsOneWidget);
    expect(find.text('LIKELY'), findsNothing);  // the device said all of it itself

    await tester.tap(find.byTooltip('All devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.42.0.100').last);
    await tester.pumpAndSettle();
    expect(find.text('Lenovo'), findsWidgets);
    expect(find.text('Windows'), findsWidgets);
    expect(find.text('LIKELY'), findsWidgets);  // MAC vendor and TTL are guesses
  });

  testWidgets('Node Inspect lets the user say what a device is', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final pc = DiscoveredDevice(
      ip: '10.42.0.100',
      vendor: 'LCFC(Hefei) Electronics Technology co., ltd',
      ttl: 128,
      sources: const {DiscoverySource.icmp},
      firstSeen: DateTime(2026, 10, 5),
      lastSeen: DateTime(2026, 10, 5),
    );
    final mystery = DiscoveredDevice(
      ip: '10.42.0.77',
      sources: const {DiscoverySource.icmp},
      firstSeen: DateTime(2026, 10, 5),
      lastSeen: DateTime(2026, 10, 5),
    );
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [pc, mystery]));
    await settleScan(tester);

    await scrollTo(tester, find.text('10.42.0.77'));
    await tester.tap(find.text('10.42.0.77').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('Not recognized yet'), findsOneWidget);

    await tester.tap(find.byTooltip('All devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('10.42.0.100').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('EDIT'));
    await tester.pumpAndSettle();
    final fields = find.descendant(of: find.byType(AlertDialog), matching: find.byType(TextField));
    expect(tester.widget<TextField>(fields.at(0)).controller!.text, 'Lenovo', reason: 'starts from the current guess');
    await tester.enterText(fields.at(1), 'ThinkCentre M70q');
    await tester.tap(find.text('SAVE'));
    await tester.pumpAndSettle();

    expect(find.text('ThinkCentre M70q'), findsWidgets);
    expect(find.text('SET BY YOU'), findsNothing);
    expect(find.text('Model · set by you'), findsOneWidget);
  });

  testWidgets('Node Inspect CONFIRM button confirms recognition, removes LIKELY, and saves label', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final pc = DiscoveredDevice(
      ip: '10.42.0.100',
      vendor: 'LCFC(Hefei) Electronics Technology co., ltd',
      ttl: 128,
      sources: const {DiscoverySource.icmp},
      firstSeen: DateTime(2026, 10, 5),
      lastSeen: DateTime(2026, 10, 5),
    );
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [pc]));
    await settleScan(tester);

    await scrollTo(tester, find.text('10.42.0.100'));
    await tester.tap(find.text('10.42.0.100').first);
    await tester.pumpAndSettle();

    expect(find.text('LIKELY'), findsWidgets);
    expect(find.text('CONFIRM'), findsWidgets);

    await tester.tap(find.text('CONFIRM').first);
    await tester.pumpAndSettle();

    expect(find.text('CONFIRM'), findsNothing);
    expect(find.text('LIKELY'), findsNothing);
    expect(find.text('SET BY YOU'), findsNothing);
  });


  testWidgets('the phone running the app is tagged THIS DEVICE', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: true));
    await tester.pump();
    bridge.devices!
      ..add(dev(testLan.ip, hostname: 'Pixel-8-Pro', rtt: 1))
      ..add(dev('10.42.0.20', hostname: 'Living Room TV', rtt: 4));
    await tester.pump();

    await scrollTo(tester, find.text('Pixel-8-Pro'));
    expect(find.text('THIS DEVICE'), findsOneWidget);
    final card = find.ancestor(of: find.text('THIS DEVICE'), matching: find.byType(DeviceCard));
    expect(find.descendant(of: card, matching: find.text('Pixel-8-Pro')), findsOneWidget);
    await settleScan(tester);
  });

  testWidgets('tapping a device card opens Node Inspect under Tools', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      await app(tester, onboarded: true, cached: [dev('10.42.0.20', hostname: 'Living Room TV')]),
    );
    await settleScan(tester);

    await scrollTo(tester, find.text('Living Room TV'));
    await tester.tap(find.text('Living Room TV').first);
    await tester.pumpAndSettle();
    expect(find.text('NODE INSPECT'), findsOneWidget);
    // Back from the device goes to the picker, then to the Tools hub.
    await tester.tap(find.byTooltip('All devices'));
    await tester.pumpAndSettle();
    expect(find.text('TOOLS  /  NODE INSPECT', findRichText: true), findsOneWidget);
    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    expect(find.text('Node Inspect'), findsOneWidget);
    await tester.tap(find.text('Node Inspect'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Living Room TV').last);
    await tester.pumpAndSettle();
    expect(find.text('LAYER 2 TELEMETRY & RTT'), findsOneWidget);

    // Topology is parked: no tab, but the screen still builds (test below).
    expect(find.text('TOPOLOGY'), findsNothing);
    expect(find.text('OVERVIEW'), findsOneWidget);

    // The agent now lives under Tools.
    await tester.tap(find.text('TOOLS'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('All devices'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Tools'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Homelab Agent'));
    await tester.pumpAndSettle();
    expect(find.text('No agent paired'), findsOneWidget);
    expect(find.text('TOOLS  /  HOMELAB AGENT', findRichText: true), findsOneWidget);

    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Add monitoring unit'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('1 device on 1 network'), 200);
    expect(find.text('1 device on 1 network'), findsOneWidget);
  });

  testWidgets('the parked Topology screen still renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    bridge = FakeBridge();
    final store = memoryStore();
    addTearDown(store.close);
    final cached = dev('10.42.0.20', hostname: 'Living Room TV', rtt: 4);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          scannerBridgeProvider.overrideWithValue(bridge),
          localStoreProvider.overrideWithValue(store),
          restoredScanProvider.overrideWithValue(ScanState(devices: {cached.ip: cached})),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const Scaffold(body: TopologyScreen()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE SUBNET'), findsOneWidget);
    expect(find.text('Living Room TV'), findsWidgets);
  });

  testWidgets('off Wi-Fi the Overview hides all data; reconnecting rescans', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      await app(tester, onboarded: true, connected: false, cached: [dev('10.42.0.20', hostname: 'Living Room TV')]),
    );
    await tester.pumpAndSettle();

    expect(find.text('Not connected to Wi-Fi'), findsOneWidget);
    expect(find.text('Living Room TV'), findsNothing);
    expect(find.text('INTERFACE TELEMETRY'), findsNothing);
    expect(find.text('OFFLINE'), findsOneWidget); // header chip

    // Wi-Fi comes back: data returns and a fresh scan starts.
    final scansBefore = bridge.scans;
    lan.set(true);
    await tester.pump();
    await tester.pump();
    expect(find.text('Not connected to Wi-Fi'), findsNothing);
    expect(find.text('INTERFACE TELEMETRY'), findsOneWidget);
    expect(bridge.scans, greaterThan(scansBefore));

    // Wi-Fi drops mid-scan: the scan is cancelled and the data hidden again.
    final cancelsBefore = bridge.cancels;
    lan.set(false);
    await tester.pump();
    expect(bridge.cancels, cancelsBefore + 1);
    expect(find.text('Not connected to Wi-Fi'), findsOneWidget);
    await bridge.finish(cancelled: true);
    await tester.pumpAndSettle();
  });

  testWidgets('the header chip opens My Networks', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [dev('10.42.0.20'), dev('10.42.0.21')]));
    await tester.pump();
    bridge.devices!.add(dev('10.42.0.20', rtt: 3));
    await bridge.finish(count: 1);
    await tester.pumpAndSettle();

    // Found through its accessibility label, which screen readers announce.
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel(RegExp('^My networks')));
    semantics.dispose();
    await tester.pumpAndSettle();
    expect(find.text('MY NETWORKS'), findsOneWidget);
    expect(find.text('CyberLab_5G'), findsOneWidget);
    expect(find.text('CONNECTED'), findsOneWidget);
    expect(find.text('2'), findsOneWidget); // devices on that network

    await tester.tap(find.text('FORGET NETWORK'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('FORGET'));
    await tester.pumpAndSettle();
    expect(find.text('No saved networks yet'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('OVERVIEW'), findsOneWidget);
  });

  testWidgets('account tab has settings section and app settings menu item', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: true));
    await settleScan(tester);

    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();

    expect(find.byTooltip('Settings'), findsNothing);
    await showAppSettingsRow(tester);
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);

    await openAppSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('APP SETTINGS'), findsOneWidget);
    expect(find.text('APP'), findsOneWidget);
    expect(find.text('USER SETTINGS'), findsOneWidget);
    expect(find.text('SCANNING'), findsOneWidget);
    expect(find.text('CLOUD & ALERTS'), findsOneWidget);

    await tester.tap(find.text('USER SETTINGS'));
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT DELETION'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT'), findsWidgets);
  });

  testWidgets('account tab displays Made on Long Island tag in about panel', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: true));
    await settleScan(tester);

    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Made on Long Island'), 200);
    expect(find.text('Made on Long Island'), findsOneWidget);

    await tester.scrollUntilVisible(find.text(AppVersion.display), 200);
    expect(find.text('${AppVersion.gitCommit} · ${AppVersion.buildDate}'), findsOneWidget);
    expect(find.text('AGENT VERSION'), findsNothing, reason: 'no agent paired');
  });

  testWidgets("about shows the paired agent's version", (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final agent = PairedAgent(id: 'a1', networkId: 'n1', name: 'homelab', version: '0.3.1', createdAt: DateTime(2026));
    await tester.pumpWidget(await app(tester, onboarded: true, agents: [agent]));
    await settleScan(tester);

    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('AGENT VERSION'), 200);
    expect(find.text('0.3.1'), findsOneWidget);
  });

  Future<void> openSignIn(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    expect(find.text('Not signed in'), findsOneWidget);
    await tester.tap(find.text('SIGN IN OR CREATE ACCOUNT'));
    await tester.pumpAndSettle();
  }

  Future<void> fill(WidgetTester tester, {String? email, String? password, String? code}) async {
    if (email != null) await tester.enterText(find.byKey(const Key('email')), email);
    if (password != null) await tester.enterText(find.byKey(const Key('password')), password);
    if (code != null) await tester.enterText(find.byKey(const Key('code')), code);
  }

  /// A toast (SnackBar) whose text contains [text].
  Finder toast(String text) => find.descendant(of: find.byType(SnackBar), matching: find.textContaining(text));

  Finder pdButton(String label) => find.byWidgetPredicate((w) => w is PdButton && w.label == label);

  /// Taps the button labelled [text], not a title that reads the same.
  Future<void> tapText(WidgetTester tester, String text) async {
    final button = find
        .ancestor(of: find.text(text), matching: find.byWidgetPredicate((w) => w is PdButton || w is TextButton))
        .first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
  }

  testWidgets('creating an account waits for the emailed link, then signs in', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true));
    await settleScan(tester);
    await openSignIn(tester);
    await tapText(tester, 'CREATE ACCOUNT');

    await fill(tester, email: 'not-an-email', password: 'longenough');
    await tapText(tester, 'CREATE ACCOUNT');
    expect(find.text('Enter a valid email address.'), findsOneWidget);

    await fill(tester, email: ' duck@example.com ', password: 'short');
    await tapText(tester, 'CREATE ACCOUNT');
    expect(find.textContaining('at least 8 characters'), findsOneWidget);

    await fill(tester, password: 'quackquack');
    await tapText(tester, 'CREATE ACCOUNT');
    expect(find.textContaining('We sent a link to duck@example.com'), findsOneWidget);
    expect(toast('Confirmation link sent to duck@example.com'), findsOneWidget);
    expect(auth.pending, {'duck@example.com'});

    await tapText(tester, 'RESEND LINK');
    expect(toast('Sent a new link to duck@example.com'), findsOneWidget);

    await tapText(tester, 'I’VE CONFIRMED');
    expect(toast('Not confirmed yet'), findsOneWidget);

    // Clicked on another device: the screen notices on its next check.
    auth.clickLink('duck@example.com');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('duck@example.com'), findsOneWidget);
    expect(find.text('SIGNED IN'), findsOneWidget);
    expect(toast('Email confirmed. You’re signed in.'), findsOneWidget);
    expect(auth.accounts, {'duck@example.com': 'quackquack'});

    await tapText(tester, 'SIGN OUT');
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('DELETE ACCOUNT'), findsNothing);
  });

  testWidgets('returning to the app after clicking the link finishes sign-up', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true));
    await settleScan(tester);
    await openSignIn(tester);
    await tapText(tester, 'CREATE ACCOUNT');
    await fill(tester, email: 'duck@example.com', password: 'quackquack');
    await tapText(tester, 'CREATE ACCOUNT');

    auth.clickLink('duck@example.com');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();
    expect(find.text('duck@example.com'), findsOneWidget);
  });

  testWidgets('a timer check landing while the screen closes does not pop the app', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true));
    await settleScan(tester);
    await openSignIn(tester);
    await tapText(tester, 'CREATE ACCOUNT');
    await fill(tester, email: 'duck@example.com', password: 'quackquack');
    await tapText(tester, 'CREATE ACCOUNT');

    // Resume finishes sign-up, then the 5s check fires before the pop animates.
    auth.clickLink('duck@example.com');
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.text('duck@example.com'), findsOneWidget);
  });

  testWidgets('an email that has an account is told to sign in', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true, accounts: {'duck@example.com': 'quackquack'}));
    await settleScan(tester);
    await openSignIn(tester);
    await tapText(tester, 'CREATE ACCOUNT');
    await fill(tester, email: 'duck@example.com', password: 'otherpassword');
    await tapText(tester, 'CREATE ACCOUNT');
    expect(toast('already has an account'), findsOneWidget);
  });

  testWidgets('signing in checks the password', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true, accounts: {'duck@example.com': 'quackquack'}));
    await settleScan(tester);
    await openSignIn(tester);

    await fill(tester, email: 'duck@example.com', password: 'wrong');
    await tapText(tester, 'SIGN IN');
    expect(toast('Wrong email or password.'), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, PingDuckColors.critical);

    await fill(tester, password: 'quackquack');
    await tapText(tester, 'SIGN IN');
    expect(find.text('duck@example.com'), findsOneWidget);
    expect(toast('Signed in'), findsOneWidget);
    expect(tester.widget<SnackBar>(find.byType(SnackBar)).backgroundColor, isNull);
  });

  testWidgets('a forgotten password is reset with an emailed code', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true, accounts: {'duck@example.com': 'forgotten'}));
    await settleScan(tester);
    await openSignIn(tester);

    await tapText(tester, 'FORGOT PASSWORD?');
    await fill(tester, email: 'duck@example.com');
    await tapText(tester, 'EMAIL ME A CODE');
    expect(auth.resets, ['duck@example.com']);
    expect(toast('Code sent to duck@example.com'), findsOneWidget);

    await fill(tester, code: FakeAuth.goodCode, password: 'newquackquack');
    await tapText(tester, 'SET PASSWORD');
    expect(find.text('duck@example.com'), findsOneWidget);
    expect(toast('Password changed. You’re signed in.'), findsOneWidget);
    expect(auth.accounts['duck@example.com'], 'newquackquack');
  });

  testWidgets('Google is shown disabled; Apple only on iOS', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true));
    await settleScan(tester);
    await openSignIn(tester);
    final google = tester.widget<PdButton>(pdButton('Continue with Google'));
    expect(google.onPressed, isNull);
    expect(pdButton('Continue with Apple'), findsNothing);
  });

  testWidgets('iOS also shows Apple, disabled', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    try {
      await tester.pumpWidget(await app(tester, onboarded: true));
      await settleScan(tester);
      await openSignIn(tester);
      final apple = tester.widget<PdButton>(pdButton('Continue with Apple'));
      expect(apple.onPressed, isNull);
      expect(pdButton('Continue with Google'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('deleting the account asks first, then signs out', (tester) async {
    await tester.pumpWidget(await app(tester, onboarded: true, accounts: {'duck@example.com': 'quackquack'}));
    await settleScan(tester);
    await openSignIn(tester);
    await fill(tester, email: 'duck@example.com', password: 'quackquack');
    await tapText(tester, 'SIGN IN');

    await openAppSettings(tester);
    await tester.pumpAndSettle();
    await tester.tap(find.text('USER SETTINGS'));
    await tester.pumpAndSettle();

    await tapText(tester, 'DELETE ACCOUNT');
    await tapText(tester, 'CANCEL');
    expect(auth.deletions, 0);
    expect(find.text('duck@example.com'), findsOneWidget);

    await tapText(tester, 'DELETE ACCOUNT');
    await tapText(tester, 'DELETE');
    expect(auth.deletions, 1);
    expect(find.text('Not signed in'), findsOneWidget);
    expect(find.text('Account deleted'), findsOneWidget);
  });

  testWidgets('returning users do not scan on launch if setting is disabled', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final cached = dev('10.42.0.20', hostname: 'Living Room TV');
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [cached], autoScanOnLaunch: false));
    await tester.pump();
    expect(bridge.scans, 0);
  });

  testWidgets('returning users scan on launch when auto-scan setting is enabled', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final cached = dev('10.42.0.20', hostname: 'Living Room TV');
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [cached], autoScanOnLaunch: true));
    await tester.pump();
    expect(bridge.scans, 1);
  });

  testWidgets('app settings allows toggling auto-scan on launch', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: true, isPremium: true));
    await settleScan(tester);

    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    await openAppSettings(tester);
    await tester.pumpAndSettle();

    expect(find.text('Auto-scan on launch'), findsOneWidget);

    final switchFinder = find.byKey(const Key('auto_scan_switch'));
    expect(tester.widget<Switch>(switchFinder).value, isTrue);

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(await currentStore.setting('autoScanOnLaunch'), '0');

    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(await currentStore.setting('autoScanOnLaunch'), '1');
  });

  testWidgets('on Free the auto-scan switch works and grants nothing', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: true, isPremium: false));
    await settleScan(tester);

    await tester.tap(find.text('ACCOUNT'));
    await tester.pumpAndSettle();
    await openAppSettings(tester);
    await tester.pumpAndSettle();

    expect(find.textContaining('at most once every 30 minutes'), findsOneWidget);
    final switchFinder = find.byKey(const Key('auto_scan_switch'));
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();
    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(await currentStore.setting('autoScanOnLaunch'), '0');
    expect(await currentStore.setting('isPremium'), '0');
    expect(await currentStore.setting('quotaLimit'), isNull);
  });
}
