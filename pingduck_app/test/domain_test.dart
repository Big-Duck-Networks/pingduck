import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/device_details/application/diagnostics_controller.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/device_kind.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/features/scanner/presentation/discovery_screen.dart';

import 'fakes.dart';

void main() {
  group('DeviceKind', () {
    DeviceKind kind(DiscoveredDevice d) => DeviceKind.of(d, gatewayIp: '10.42.0.1');

    test('uses real signals only', () {
      expect(kind(dev('10.42.0.1')), DeviceKind.gateway);
      expect(kind(dev('10.42.0.20', hostname: 'Living Room TV', services: ['_googlecast._tcp'])), DeviceKind.media);
      expect(kind(dev('10.42.0.21', hostname: 'Nest Mini', services: ['_googlecast._tcp'])), DeviceKind.speaker);
      expect(kind(dev('10.42.0.22', hostname: 'HP9AC242', services: ['_ipp._tcp', '_printer._tcp'])), DeviceKind.printer);
      expect(kind(dev('10.42.0.23', vendor: 'QEMU/KVM virtual NIC')), DeviceKind.virtual);
      expect(kind(dev('10.42.0.24', hostname: 'mint')), DeviceKind.workstation);
      expect(kind(dev('10.42.0.25', hostname: 'Hue Bridge', services: ['_hue._tcp'])), DeviceKind.iot);
      expect(kind(dev('10.42.0.26', vendor: 'Private (randomized MAC)')), DeviceKind.mobile);
      expect(kind(dev('10.42.0.27')), DeviceKind.unknown);
    });

    test('UPnP gateway device types count as gateways', () {
      expect(kind(dev('10.42.0.9', services: ['upnp:InternetGatewayDevice'])), DeviceKind.gateway);
    });
  });

  group('DiscoveredDevice', () {
    test('merge keeps user fields and upgrades a private-MAC vendor', () {
      final cached = dev('10.0.0.5', vendor: 'Private (randomized MAC)').copyWith(customName: 'Phone', notes: 'kid');
      final merged = cached.merge(dev('10.0.0.5', vendor: 'Apple, Inc.', hostname: 'iphone'));
      expect(merged.vendor, 'Apple, Inc.');
      expect(merged.displayName, 'Phone');
      expect(merged.notes, 'kid');
      expect(dev('1.1.1.1', vendor: 'Apple').merge(dev('1.1.1.1', vendor: 'Other')).vendor, 'Apple');
    });

    test('SSDP server banners are not used as names', () {
      const banner = DiscoveredDevice(ip: '10.0.0.9', model: 'Linux/5.15, UPnP/1.0, Chromecast/1.6.18');
      expect(banner.displayName, '10.0.0.9');
      const real = DiscoveredDevice(ip: '10.0.0.9', model: 'Roku Express');
      expect(real.displayName, 'Roku Express');
    });

    test('RTT history is bounded', () {
      var d = dev('10.0.0.5');
      for (var i = 0; i < 30; i++) {
        d = d.withRttSample(i);
      }
      expect(d.rttHistory.length, DiscoveredDevice.historyLength);
      expect(d.rttHistory.last, 29);
    });

    test('DiscoverySource mask round trip', () {
      final s = {DiscoverySource.icmp, DiscoverySource.arp, DiscoverySource.ssdp};
      expect(DiscoverySource.fromMask(DiscoverySource.toMask(s)), s);
    });
  });

  test('ledger sort and filter', () {
    final devices = [
      dev('10.0.0.30', hostname: 'b', rtt: 9),
      dev('10.0.0.4', hostname: 'a', rtt: 30),
      dev('10.0.0.200', hostname: 'c').offline(),
      dev('10.0.0.7', hostname: 'd', rtt: 1),
    ];
    String ips(List<DiscoveredDevice> l) => l.map((d) => d.shortIp).join(' ');
    expect(ips(sortAndFilter(devices, LedgerSort.latency, LedgerFilter.all)), '.7 .30 .4 .200');
    expect(ips(sortAndFilter(devices, LedgerSort.ip, LedgerFilter.all)), '.4 .7 .30 .200');
    expect(ips(sortAndFilter(devices, LedgerSort.name, LedgerFilter.online)), '.4 .30 .7');
    expect(ips(sortAndFilter(devices, LedgerSort.ip, LedgerFilter.offline)), '.200');
  });

  group('diagnostics', () {
    test('stats: min, avg, max, jitter, loss', () {
      const s = DiagnosticsState(pings: [10, 12, null, 8, 10]);
      expect(s.minRtt, 8);
      expect(s.maxRtt, 12);
      expect(s.avgRtt, 10);
      expect(s.jitter, (2 + 4 + 2) / 3);
      expect(s.lossPercent, 20);
    });

    test('ping monitor, port scan and wake-on-LAN go through the bridge', () async {
      final bridge = FakeBridge()
        ..pingReplies = [3, null, 5]
        ..open = {22, 445, 3389, 8000};
      final c = ProviderContainer(overrides: [scannerBridgeProvider.overrideWithValue(bridge)]);
      addTearDown(c.dispose);
      final sub = c.listen(diagnosticsProvider('10.42.0.5'), (_, _) {});
      addTearDown(sub.close);
      final ctrl = c.read(diagnosticsProvider('10.42.0.5').notifier);

      ctrl.startPing(interval: const Duration(milliseconds: 10));
      await Future<void>.delayed(const Duration(milliseconds: 60));
      ctrl.stopPing();
      expect(c.read(diagnosticsProvider('10.42.0.5')).pings.take(3), [3, null, 5]);

      await ctrl.scanPorts();
      var s = c.read(diagnosticsProvider('10.42.0.5'));
      expect(s.portScan, PortScanState.done);
      expect(s.openPorts, {22, 445, 3389});  // 8000 is not a quick-scan port
      expect(bridge.probedPorts!.length, commonPorts.length);

      await ctrl.scanPorts(deep: true);
      expect(bridge.probedPorts!.length, 1024);

      await ctrl.wake('aa:bb:cc:dd:ee:ff', broadcast: '10.42.0.255');
      s = c.read(diagnosticsProvider('10.42.0.5'));
      expect(bridge.wokenMac, 'aa:bb:cc:dd:ee:ff');
      expect(s.wolSentAt, isNotNull);
    });
  });
}
