import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/ffi/scanner_bridge.dart';
import 'package:pingduck_app/core/network/network_context.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/services/local_storage.dart';

import 'fakes.dart';

void main() {
  late FakeBridge bridge;
  late FakeLock lock;
  late LocalStore store;
  late ProviderContainer container;

  ProviderContainer make({ScanState restored = const ScanState()}) => ProviderContainer(overrides: [
        scannerBridgeProvider.overrideWithValue(bridge),
        multicastLockProvider.overrideWithValue(lock),
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(restored),
      ]);

  setUp(() {
    bridge = FakeBridge();
    lock = FakeLock();
    store = memoryStore();
    container = make();
  });
  tearDown(() async {
    container.dispose();
    await store.close();
  });

  ScanController ctrl() => container.read(scanControllerProvider.notifier);
  ScanState state() => container.read(scanControllerProvider);

  Future<void> runScan(List<dynamic> devices, {int? count}) async {
    final running = ctrl().scan();
    await pumpEventQueue();
    for (final d in devices) {
      bridge.devices!.add(d);
    }
    await pumpEventQueue();
    await bridge.finish(count: count ?? devices.length);
    await running;
  }

  test('streams devices in, scans the LAN subnet, and finishes', () async {
    final running = ctrl().scan();
    await pumpEventQueue();
    expect(state().phase, ScanPhase.scanning);
    expect(state().lan?.cidr, '10.42.0.0/24');
    expect(bridge.lastCidr, '10.42.0.0/24');
    expect(lock.held, 1);

    bridge.devices!.add(dev('10.42.0.20', rtt: 3));
    bridge.devices!.add(dev('10.42.0.1'));
    bridge.devices!.add(dev('10.42.0.20', hostname: 'Living Room TV', rtt: 3));
    await pumpEventQueue();
    expect(state().devices.length, 2);
    expect(state().devices['10.42.0.20']!.hostname, 'Living Room TV');
    expect(state().devices['10.42.0.20']!.rttHistory, [3]);  // one sample per scan

    await bridge.finish(count: 2);
    await running;
    expect(state().phase, ScanPhase.done);
    expect(state().sortedDevices.map((d) => d.ip), ['10.42.0.1', '10.42.0.20']);
    expect(lock.held, 0);
  });

  test('a second scan keeps old devices offline until they answer', () async {
    await runScan([dev('10.42.0.5', hostname: 'nas', rtt: 2), dev('10.42.0.6')]);

    final running = ctrl().scan();
    await pumpEventQueue();
    expect(state().devices.values.every((d) => !d.isOnline), isTrue);
    bridge.devices!.add(dev('10.42.0.5', rtt: 4));  // ICMP-only report this time
    await pumpEventQueue();
    expect(state().devices['10.42.0.5']!.isOnline, isTrue);
    expect(state().devices['10.42.0.5']!.hostname, 'nas');
    expect(state().devices['10.42.0.5']!.rttHistory, [2, 4]);
    expect(state().devices['10.42.0.6']!.isOnline, isFalse);
    await bridge.finish(count: 1);
    await running;
  });

  test('scans persist, and a restart restores the inventory offline', () async {
    await runScan([dev('10.42.0.5', hostname: 'nas', rtt: 2, services: ['_smb._tcp'])]);
    await ctrl().rename('10.42.0.5', 'Vault');
    await ctrl().setNotes('10.42.0.5', 'rack 2');

    final restored = await restoreLastScan(store);
    expect(restored.devices.length, 1);
    final d = restored.devices['10.42.0.5']!;
    expect(d.isOnline, isFalse);
    expect(d.displayName, 'Vault');
    expect(d.hostname, 'nas');
    expect(d.notes, 'rack 2');
    expect(d.services, ['_smb._tcp']);
    expect(d.rttHistory, [2]);

    container.dispose();
    container = make(restored: restored);
    expect(state().devices['10.42.0.5']!.customName, 'Vault');

    // A later scan's report never overwrites the user's name.
    await runScan([dev('10.42.0.5', hostname: 'diskstation', rtt: 1)]);
    expect(state().devices['10.42.0.5']!.displayName, 'Vault');
  });

  test('the list is titled with the Wi-Fi name, remembered across restarts', () async {
    expect(state().networkTitle, 'This network');
    await runScan([dev('10.42.0.5')]);
    expect(state().networkTitle, 'CyberLab_5G');
    expect((await restoreLastScan(store)).networkName, 'CyberLab_5G');

    // Without location access the OS hides the name: keep the remembered one.
    bridge.lan = const LanInfo(ip: '10.42.0.17', cidr: '10.42.0.0/24', gateway: '10.42.0.1');
    await runScan([dev('10.42.0.5')]);
    expect(state().networkTitle, 'CyberLab_5G');

    // A network never seen with a name falls back to its subnet.
    bridge.lan = const LanInfo(ip: '192.168.1.9', cidr: '192.168.1.0/24', gateway: '192.168.1.1');
    await runScan([]);
    expect(state().networkTitle, '192.168.1.0/24');
  });

  test('cleanSsid strips Android quoting and placeholders', () {
    expect(cleanSsid('"CyberLab_5G"'), 'CyberLab_5G');
    expect(cleanSsid('<unknown ssid>'), isNull);
    expect(cleanSsid(''), isNull);
    expect(cleanSsid(null), isNull);
  });

  test('renaming to blank restores the discovered name', () async {
    await runScan([dev('10.42.0.5', hostname: 'nas')]);
    await ctrl().rename('10.42.0.5', 'Vault');
    await ctrl().rename('10.42.0.5', '  ');
    expect(state().devices['10.42.0.5']!.displayName, 'nas');
  });

  test('switching networks swaps in that network\'s cache', () async {
    await runScan([dev('10.42.0.5')]);
    bridge.lan = const LanInfo(ip: '192.168.1.9', cidr: '192.168.1.0/24', gateway: '192.168.1.1');
    final running = ctrl().scan();
    await pumpEventQueue();
    expect(state().devices, isEmpty);
    await bridge.finish();
    await running;

    bridge.lan = testLan;
    final back = ctrl().scan();
    await pumpEventQueue();
    expect(state().devices.keys, ['10.42.0.5']);
    await bridge.finish();
    await back;
  });

  test('clearInventory wipes devices and networks but keeps settings', () async {
    await runScan([dev('10.42.0.5'), dev('10.42.0.6')]);
    await store.setSetting('onboarded', '1');
    expect(await store.usage(), (networks: 1, devices: 2));

    await ctrl().clearInventory();
    expect(state().devices, isEmpty);
    expect(await store.usage(), (networks: 0, devices: 0));
    expect((await restoreLastScan(store)).devices, isEmpty);
    expect(await store.setting('onboarded'), '1');
  });

  test('networks are listed with counts and can be forgotten', () async {
    await runScan([dev('10.42.0.5'), dev('10.42.0.6')]);
    bridge.lan = const LanInfo(ip: '192.168.1.9', cidr: '192.168.1.0/24', gateway: '192.168.1.1');
    await runScan([dev('192.168.1.20')]);

    var list = await store.networkSummaries();
    expect(list.map((n) => (n.name, n.deviceCount)), [('192.168.1.0/24', 1), ('CyberLab_5G', 2)]);

    // Forgetting another network leaves the one on screen alone.
    final home = list.firstWhere((n) => n.ssid == 'CyberLab_5G');
    await ctrl().forgetNetwork(home.id);
    expect(state().devices.keys, ['192.168.1.20']);
    list = await store.networkSummaries();
    expect(list.map((n) => n.cidr), ['192.168.1.0/24']);
    expect(await store.usage(), (networks: 1, devices: 1));

    // Forgetting the one on screen empties it.
    await ctrl().forgetNetwork(list.single.id);
    expect(state().devices, isEmpty);
    expect(await store.networkSummaries(), isEmpty);
  });

  test('forget removes a device everywhere', () async {
    await runScan([dev('10.42.0.5'), dev('10.42.0.6')]);
    await ctrl().forget('10.42.0.6');
    expect(state().devices.keys, ['10.42.0.5']);
    expect((await restoreLastScan(store)).devices.keys, ['10.42.0.5']);
  });

  test('cancel forwards to the bridge and ends as cancelled', () async {
    final running = ctrl().scan();
    await pumpEventQueue();
    ctrl().cancel();
    expect(bridge.cancels, 1);
    await bridge.finish(cancelled: true);
    await running;
    expect(state().phase, ScanPhase.cancelled);
    ctrl().cancel();  // not scanning: ignored
    expect(bridge.cancels, 1);
  });

  test('no network fails fast without scanning', () async {
    bridge.lan = null;
    await ctrl().scan();
    expect(state().phase, ScanPhase.failed);
    expect(state().failure!.kind, ScanFailureKind.noNetwork);
    expect(bridge.scans, 0);
  });

  test('failures surface with their kind and release the lock', () async {
    final running = ctrl().scan();
    await pumpEventQueue();
    await bridge.finish(failure: const ScanFailure(ScanFailureKind.permission, 'denied'));
    await running;
    expect(state().phase, ScanPhase.failed);
    expect(state().failure!.kind, ScanFailureKind.permission);
    expect(lock.held, 0);
  });

  test('scan while scanning is ignored', () async {
    final running = ctrl().scan();
    await pumpEventQueue();
    await ctrl().scan();
    expect(bridge.scans, 1);
    await bridge.finish();
    await running;
  });

  test('NetworkContext.cidr and LanInfo.broadcast', () {
    expect(const NetworkContext(ip: '10.42.0.17', subnetMask: '255.255.255.0').cidr, '10.42.0.0/24');
    expect(const NetworkContext(ip: '10.1.2.3', subnetMask: '255.0.0.0').cidr, '10.1.0.0/16');
    expect(const NetworkContext(ip: '10.42.0.17').cidr, isNull);
    expect(testLan.broadcast, '10.42.0.255');
    expect(const LanInfo(ip: '10.1.2.3', cidr: '10.1.0.0/16').broadcast, '10.1.255.255');
  });
}
