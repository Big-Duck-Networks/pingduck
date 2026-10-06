import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/core/network/lan_connectivity.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/topology/presentation/topology_screen.dart';
import 'package:pingduck_app/main.dart';

import 'fakes.dart';

void main() {
  late FakeBridge bridge;
  late FakeLan lan;

  /// Seeds the cache like a previous session did, then restores from it the
  /// way main() does.
  Future<Widget> app(WidgetTester tester,
      {required bool onboarded, List<DiscoveredDevice> cached = const [], bool connected = true}) async {
    bridge = FakeBridge();
    lan = FakeLan(connected);
    final store = memoryStore();
    addTearDown(store.close);
    final restored = await tester.runAsync(() async {
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
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(restored!),
        onboardedProvider.overrideWith(() => Onboarded(onboarded)),
        lanConnectivityProvider.overrideWithValue(lan),
      ],
      child: const PingDuckApp(),
    );
  }

  /// The ledger sits below the radar, outside the lazily built viewport.
  Future<void> scrollTo(WidgetTester tester, Finder f) =>
      tester.scrollUntilVisible(f, 300,
          scrollable: find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first);

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
    expect(find.text('CyberLab_5G'), findsOneWidget);  // remembered from the last scan
    await tester.pump();
    expect(bridge.scans, 1);  // returning users get a scan on launch

    bridge.devices!.add(dev('10.42.0.20', rtt: 4));
    await tester.pump();
    expect(find.text('4 ms', findRichText: true), findsWidgets);
    await settleScan(tester);
  });

  testWidgets('tapping a device card opens Node Inspect under Tools', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester, onboarded: true, cached: [dev('10.42.0.20', hostname: 'Living Room TV')]));
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
    expect(find.text('1 device on 1 network'), findsOneWidget);
  });

  testWidgets('the parked Topology screen still renders', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    bridge = FakeBridge();
    final store = memoryStore();
    addTearDown(store.close);
    final cached = dev('10.42.0.20', hostname: 'Living Room TV', rtt: 4);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scannerBridgeProvider.overrideWithValue(bridge),
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(ScanState(devices: {cached.ip: cached})),
      ],
      child: MaterialApp(theme: PingDuckTheme.light(), home: const Scaffold(body: TopologyScreen())),
    ));
    await tester.pumpAndSettle();
    expect(find.text('ACTIVE SUBNET'), findsOneWidget);
    expect(find.text('Living Room TV'), findsWidgets);
  });

  testWidgets('off Wi-Fi the Overview hides all data; reconnecting rescans', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await app(tester,
        onboarded: true, connected: false, cached: [dev('10.42.0.20', hostname: 'Living Room TV')]));
    await tester.pumpAndSettle();

    expect(find.text('Not connected to Wi-Fi'), findsOneWidget);
    expect(find.text('Living Room TV'), findsNothing);
    expect(find.text('INTERFACE TELEMETRY'), findsNothing);
    expect(find.text('OFFLINE'), findsOneWidget);  // header chip

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
    expect(find.text('2'), findsOneWidget);  // devices on that network

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
    expect(find.text('SETTINGS'), findsOneWidget);
    expect(find.text('App settings'), findsOneWidget);

    await tester.tap(find.text('App settings'));
    await tester.pumpAndSettle();

    expect(find.text('APP SETTINGS'), findsOneWidget);
    expect(find.text('SCANNING'), findsOneWidget);
    expect(find.text('CLOUD & ALERTS'), findsOneWidget);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.text('ACCOUNT'), findsWidgets);
  });
}

