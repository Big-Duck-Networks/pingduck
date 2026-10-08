// Store listing screenshots: the real UI on a made-up demo network, so the
// captures are repeatable and show no real devices. Run on a phone emulator:
//
//   flutter drive -d emulator-5554 \
//     --driver=test_driver/screenshot_driver.dart \
//     --target=integration_test/store_screenshots_test.dart
//
// Raw captures land in store/google-play/raw/; store/google-play/compose.py
// frames and captions them.
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pingduck_app/core/network/lan_connectivity.dart';
import 'package:pingduck_app/core/network/network_context.dart';
import 'package:pingduck_app/core/ffi/scanner_bridge.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/main.dart';

import '../test/fakes.dart';

const demoLan = LanInfo(
  ip: '192.168.1.57',
  cidr: '192.168.1.0/24',
  gateway: '192.168.1.1',
  interfaceName: 'wlan0',
  ssid: 'Duck Pond',
);

DiscoveredDevice _d(
  String host,
  String name, {
  String? vendor,
  String? model,
  int? rtt,
  List<String> services = const [],
  Set<DiscoverySource> sources = const {DiscoverySource.icmp},
  List<int> history = const [],
  bool online = true,
}) =>
    DiscoveredDevice(
      ip: '192.168.1.$host',
      hostname: name,
      vendor: vendor,
      model: model,
      rttMs: online ? rtt : null,
      services: services,
      sources: sources,
      isOnline: online,
      firstSeen: DateTime(2026, 9, 12),
      lastSeen: DateTime(2026, 10, 8),
      rttHistory: history,
    );

const _all = {DiscoverySource.icmp, DiscoverySource.mdns, DiscoverySource.ssdp};
const _icmpMdns = {DiscoverySource.icmp, DiscoverySource.mdns};

final demoDevices = [
  _d('1', 'Router', vendor: 'TP-Link', model: 'Archer AX55', rtt: 2, sources: _all, services: ['_http._tcp'],
      history: [2, 3, 2, 2, 4, 2, 3, 2]),
  _d('10', 'Synology NAS', vendor: 'Synology', model: 'DS220+', rtt: 3, sources: _icmpMdns,
      services: ['_smb._tcp', '_http._tcp', '_afpovertcp._tcp'], history: [3, 4, 3, 3, 5, 3, 4, 3]),
  _d('23', 'Living Room TV', vendor: 'Samsung', rtt: 8, sources: _all, services: ['_airplay._tcp'],
      history: [9, 8, 12, 8, 7, 9, 8, 8]),
  _d('31', 'Kitchen Speaker', vendor: 'Google', rtt: 14, sources: _all, services: ['_googlecast._tcp'],
      history: [15, 14, 18, 13, 14, 16, 14, 14]),
  _d('42', 'Hue Bridge', vendor: 'Signify', rtt: 5, sources: _icmpMdns, services: ['_hue._tcp'],
      history: [5, 6, 5, 5, 7, 5, 5, 5]),
  _d('57', 'MacBook Pro', vendor: 'Apple', rtt: 4, sources: _icmpMdns, services: ['_ssh._tcp', '_smb._tcp'],
      history: [4, 5, 4, 6, 4, 4, 5, 4]),
  _d('64', 'iPhone', vendor: 'Apple', rtt: 38, sources: _icmpMdns, services: ['_companion-link._tcp'],
      history: [41, 35, 52, 38, 33, 44, 38, 38]),
  _d('77', 'Office Printer', vendor: 'HP', model: 'OfficeJet Pro 9015', rtt: 22, sources: _all,
      services: ['_ipp._tcp', '_printer._tcp'], history: [21, 25, 22, 20, 23, 22, 24, 22]),
  _d('88', 'Thermostat', vendor: 'ecobee', rtt: 61, history: [58, 66, 61, 70, 59, 61, 64, 61]),
  _d('102', 'Front Doorbell', vendor: 'Ring', rtt: 124, history: [110, 131, 124, 140, 118, 124, 129, 124]),
  _d('115', 'Xbox Series X', vendor: 'Microsoft', rtt: 9, sources: _icmpMdns, history: [9, 10, 9, 11, 9, 9, 10, 9]),
  _d('130', 'pihole', vendor: 'Raspberry Pi', rtt: 2, sources: _icmpMdns, services: ['_ssh._tcp', '_http._tcp'],
      history: [2, 2, 3, 2, 2, 2, 3, 2]),
];

final offlineDevice = _d('201', 'Garage Camera', vendor: 'Wyze', online: false, history: [30, 28, 33]);

/// Reports location as granted without the system dialog, so the header shows
/// the demo Wi-Fi name and nothing blocks the run.
class _GrantedWifiName extends WifiNameAccess {
  _GrantedWifiName() : super(wasAsked: () async => true, markAsked: () async {});

  @override
  Future<bool> ensure() async => true;
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  Future<void> pumpFor(WidgetTester tester, Duration d) async {
    final end = DateTime.now().add(d);
    while (DateTime.now().isBefore(end)) {
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await pumpFor(tester, const Duration(milliseconds: 600));
    await binding.takeScreenshot(name);
  }

  testWidgets('store screenshots', (tester) async {
    final bridge = FakeBridge()..lan = demoLan;
    final store = memoryStore();

    // A previous scan, so the radar starts from cache and Garage Camera shows as offline.
    final id = await store.networkFor(key: demoLan.key, cidr: demoLan.cidr, gateway: demoLan.gateway);
    await store.saveDevices(id, [...demoDevices, offlineDevice]);
    await store.markScanned(id, DateTime(2026, 10, 7), ssid: demoLan.ssid);
    // A second saved network for My Networks.
    final cabin = await store.networkFor(key: 'demo-cabin', cidr: '10.0.0.0/24', gateway: '10.0.0.1');
    await store.saveDevices(cabin, [
      for (final (h, n) in [('1', 'Cabin Router'), ('12', 'Trail Camera'), ('20', 'Smart Plug'), ('31', 'Roku')])
        DiscoveredDevice(ip: '10.0.0.$h', hostname: n, isOnline: false, lastSeen: DateTime(2026, 8, 30)),
    ]);
    await store.markScanned(cabin, DateTime(2026, 8, 30), ssid: 'Lake Cabin');
    await store.setSetting('lastNetworkId', '$id');
    final restored = await restoreLastScan(store);

    await binding.convertFlutterSurfaceToImage();
    await tester.pumpWidget(ProviderScope(
      overrides: [
        scannerBridgeProvider.overrideWithValue(bridge),
        multicastLockProvider.overrideWithValue(FakeLock()),
        scanQuotaProvider.overrideWithValue(FakeQuota()),
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(restored),
        onboardedProvider.overrideWith(() => Onboarded(true)),
        lanConnectivityProvider.overrideWithValue(FakeLan()),
        accountAuthProvider.overrideWithValue(FakeAuth()),
        wifiNameAccessProvider.overrideWithValue(_GrantedWifiName()),
      ],
      child: const PingDuckApp(),
    ));

    // The launch scan: devices answer one by one, then it finishes.
    while (bridge.devices == null) {
      await pumpFor(tester, const Duration(milliseconds: 50));
    }
    for (final d in demoDevices) {
      bridge.devices!.add(d);
      await pumpFor(tester, const Duration(milliseconds: 120));
    }
    await bridge.finish(count: demoDevices.length);
    await pumpFor(tester, const Duration(seconds: 2));
    await shot(tester, '01_overview');

    // The ledger below the radar.
    final scrollable = find.descendant(of: find.byType(CustomScrollView), matching: find.byType(Scrollable)).first;
    final sortControl = find.textContaining('SORT:');
    await tester.scrollUntilVisible(sortControl, 300, scrollable: scrollable);
    // Bring the ledger's sort/filter row up under the app bar (a jump, not a
    // drag, so there is no fling overshoot).
    await Scrollable.ensureVisible(tester.element(sortControl), alignment: 0);
    tester.state<ScrollableState>(scrollable).position.jumpTo(
      tester.state<ScrollableState>(scrollable).position.pixels - 90,
    );
    await shot(tester, '02_devices');

    // Node Inspect on the NAS, with a port scan and live ping.
    bridge.open = {22, 80, 139, 443, 445, 5000, 5001};
    bridge.pingReplies = [3, 4, 3, 3, 5, 3, 4, 3, 6, 3, 3, 4, 3, 3, 4, 3, 5, 3, 3, 4, 3, 3, 4, 3, 3];
    await tester.ensureVisible(find.text('Synology NAS'));
    await pumpFor(tester, const Duration(milliseconds: 400));
    await tester.tap(find.text('Synology NAS'));
    await pumpFor(tester, const Duration(seconds: 1));
    await shot(tester, '03_inspect');

    await tester.ensureVisible(find.text('LIVE PING'));
    await tester.tap(find.text('LIVE PING'));
    await tester.ensureVisible(find.text('QUICK SCAN'));
    await tester.tap(find.text('QUICK SCAN'));
    await pumpFor(tester, const Duration(seconds: 22));
    await tester.ensureVisible(find.text('LIVE PING').evaluate().isEmpty ? find.text('STOP') : find.text('LIVE PING'));
    await shot(tester, '04_diagnostics');

    // My Networks, from the header chip (always on screen).
    await tester.tap(find.text('OVERVIEW'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    final semantics = tester.ensureSemantics();
    await tester.tap(find.bySemanticsLabel(RegExp('^My networks')));
    semantics.dispose();
    await pumpFor(tester, const Duration(milliseconds: 800));
    await shot(tester, '05_networks');
    await tester.tap(find.byTooltip('Back'));
    await pumpFor(tester, const Duration(milliseconds: 500));

    // Account: no sign-up needed.
    await tester.tap(find.text('ACCOUNT'));
    await pumpFor(tester, const Duration(milliseconds: 500));
    await shot(tester, '06_account');
  });
}
