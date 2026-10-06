import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/ffi/scanner_bridge.dart';
import 'package:pingduck_app/core/network/network_context.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';

/// Scripted bridge: the test pushes devices and then finishes the scan.
class FakeBridge implements ScannerBridge {
  StreamController<DiscoveredDevice>? devices;
  Completer<ScanSummary>? done;
  int scans = 0, cancels = 0;

  @override
  BridgeScan scan({Duration timeout = const Duration(seconds: 3)}) {
    scans++;
    devices = StreamController();
    done = Completer();
    return BridgeScan(devices!.stream, done!.future);
  }

  @override
  void cancel() => cancels++;

  Future<void> finish({int count = 0, bool cancelled = false, ScanFailure? failure}) async {
    await devices!.close();
    failure == null
        ? done!.complete(ScanSummary(deviceCount: count, cancelled: cancelled))
        : done!.completeError(failure);
  }
}

class FakeLock implements MulticastLock {
  int held = 0;
  @override
  Future<void> acquire() async => held++;
  @override
  Future<void> release() async => held--;
}

void main() {
  late FakeBridge bridge;
  late FakeLock lock;
  late ProviderContainer container;

  setUp(() {
    bridge = FakeBridge();
    lock = FakeLock();
    container = ProviderContainer(overrides: [
      scannerBridgeProvider.overrideWithValue(bridge),
      multicastLockProvider.overrideWithValue(lock),
    ]);
  });
  tearDown(() => container.dispose());

  ScanController ctrl() => container.read(scanControllerProvider.notifier);
  ScanState state() => container.read(scanControllerProvider);

  DiscoveredDevice dev(String ip, {String? hostname, int? rtt}) => DiscoveredDevice(
        ip: ip,
        hostname: hostname,
        rttMs: rtt,
        isOnline: true,
        sources: const {DiscoverySource.icmp},
      );

  test('streams devices in and finishes', () async {
    final running = ctrl().scan();
    await pumpEventQueue();
    expect(state().phase, ScanPhase.scanning);
    expect(lock.held, 1);

    bridge.devices!.add(dev('10.42.0.20', rtt: 3));
    bridge.devices!.add(dev('10.42.0.1'));
    bridge.devices!.add(dev('10.42.0.20', hostname: 'Living Room TV'));
    await pumpEventQueue();
    expect(state().devices.length, 2);
    expect(state().devices['10.42.0.20']!.hostname, 'Living Room TV');
    expect(state().devices['10.42.0.20']!.rttMs, 3);

    await bridge.finish(count: 2);
    await running;
    expect(state().phase, ScanPhase.done);
    expect(state().sortedDevices.map((d) => d.ip), ['10.42.0.1', '10.42.0.20']);
    expect(lock.held, 0);
  });

  test('a second scan keeps old devices offline until they answer', () async {
    var running = ctrl().scan();
    await pumpEventQueue();
    bridge.devices!.add(dev('10.42.0.5', hostname: 'nas'));
    bridge.devices!.add(dev('10.42.0.6'));
    await bridge.finish(count: 2);
    await running;

    running = ctrl().scan();
    await pumpEventQueue();
    expect(state().devices.values.every((d) => !d.isOnline), isTrue);
    bridge.devices!.add(dev('10.42.0.5'));  // ICMP-only report this time
    await pumpEventQueue();
    expect(state().devices['10.42.0.5']!.isOnline, isTrue);
    expect(state().devices['10.42.0.5']!.hostname, 'nas');  // kept from last scan
    expect(state().devices['10.42.0.6']!.isOnline, isFalse);
    expect(state().sortedDevices.first.ip, '10.42.0.5');
    await bridge.finish(count: 1);
    await running;
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

  test('failures surface with their kind and release the lock', () async {
    final running = ctrl().scan();
    await pumpEventQueue();
    await bridge.finish(failure: const ScanFailure(ScanFailureKind.noNetwork, 'offline'));
    await running;
    expect(state().phase, ScanPhase.failed);
    expect(state().failure!.kind, ScanFailureKind.noNetwork);
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

  test('NetworkContext.cidr', () {
    expect(const NetworkContext(ip: '10.42.0.17', subnetMask: '255.255.255.0').cidr, '10.42.0.0/24');
    expect(const NetworkContext(ip: '10.1.2.3', subnetMask: '255.0.0.0').cidr, '10.1.0.0/16');
    expect(const NetworkContext(ip: '10.42.0.17').cidr, isNull);
    expect(const NetworkContext(ip: 'x', subnetMask: '255.255.255.0').cidr, isNull);
  });
}
