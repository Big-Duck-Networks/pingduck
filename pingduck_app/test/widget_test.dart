import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/main.dart';

void main() {
  testWidgets('app boots to the radar screen', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PingDuckApp()));
    expect(find.text('PingDuck'), findsOneWidget);
  });

  test('DiscoverySource decodes the core PD_SRC_* bitmask', () {
    // PD_SRC_ICMP | PD_SRC_ARP | PD_SRC_SSDP
    expect(
      DiscoverySource.fromMask(0x1 | 0x8 | 0x4),
      {DiscoverySource.icmp, DiscoverySource.arp, DiscoverySource.ssdp},
    );
  });

  test('merge keeps known fields and unions services', () {
    const cached = DiscoveredDevice(
      ip: '10.0.0.5',
      mac: 'aa:bb:cc:dd:ee:ff',
      vendor: 'Synology',
      services: ['_smb._tcp'],
    );
    const fresh = DiscoveredDevice(
      ip: '10.0.0.5',
      hostname: 'nas',
      services: ['_http._tcp'],
      rttMs: 3,
      isOnline: true,
    );
    final merged = cached.merge(fresh);
    expect(merged.mac, 'aa:bb:cc:dd:ee:ff');
    expect(merged.hostname, 'nas');
    expect(merged.vendor, 'Synology');
    expect(merged.services, containsAll(['_smb._tcp', '_http._tcp']));
    expect(merged.isOnline, isTrue);
  });
}
