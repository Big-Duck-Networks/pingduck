import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/port_scanner/application/port_scanner_controller.dart';
import 'package:pingduck_app/features/port_scanner/domain/port_scan_models.dart';
import 'package:pingduck_app/features/port_scanner/presentation/port_scanner_screen.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/tools/presentation/tools_screen.dart';
import 'package:pingduck_app/services/local_storage.dart';

import 'fakes.dart';

void main() {
  group('cleanHostInput', () {
    test('cleans raw domain inputs correctly', () {
      expect(cleanHostInput('google.com'), 'google.com');
      expect(cleanHostInput('  GOOGLE.COM  '), 'google.com');
      expect(cleanHostInput('https://google.com/search?q=test'), 'google.com');
      expect(cleanHostInput('http://192.168.1.1:8080/admin'), '192.168.1.1');
      expect(cleanHostInput('my-nas.local:5000'), 'my-nas.local');
      expect(cleanHostInput(''), '');
    });
  });

  group('lookupPortDetails', () {
    test('identifies well known ports and risk annotations', () {
      final p80 = lookupPortDetails(80);
      expect(p80.port, 80);
      expect(p80.service, 'HTTP');
      expect(p80.risk, isNull);

      final p21 = lookupPortDetails(21);
      expect(p21.service, 'FTP');
      expect(p21.risk, 'Plaintext logins');

      final p23 = lookupPortDetails(23);
      expect(p23.service, 'Telnet');
      expect(p23.risk, 'Plaintext remote shell');

      final p3306 = lookupPortDetails(3306);
      expect(p3306.service, 'MySQL');
      expect(p3306.risk, 'Database server exposed');

      final unknown = lookupPortDetails(49152);
      expect(unknown.service, 'TCP');
      expect(unknown.risk, isNull);
    });
  });

  group('RecentPortScanHost serialization', () {
    test('encodes and decodes list cleanly', () {
      final now = DateTime(2026, 10, 27, 12, 0);
      final list = [
        RecentPortScanHost(
          host: 'google.com',
          resolvedIp: '142.250.190.46',
          timestamp: now,
          openPortsCount: 2,
          scannedPortsCount: 18,
          profile: PortScanProfile.quick,
        ),
      ];

      final encoded = RecentPortScanHost.encodeList(list);
      final decoded = RecentPortScanHost.decodeList(encoded);

      expect(decoded.length, 1);
      expect(decoded.first.host, 'google.com');
      expect(decoded.first.resolvedIp, '142.250.190.46');
      expect(decoded.first.openPortsCount, 2);
      expect(decoded.first.profile, PortScanProfile.quick);
    });
  });

  group('PortScannerController', () {
    late FakeBridge bridge;
    late ProviderContainer container;

    setUp(() {
      bridge = FakeBridge();
      bridge.open = {80, 443};
      final store = memoryStore();
      addTearDown(store.close);

      container = ProviderContainer(
        overrides: [
          scannerBridgeProvider.overrideWithValue(bridge),
          localStoreProvider.overrideWithValue(store),
          dnsLookupProvider.overrideWithValue((host) async {
            if (host == 'google.com') {
              return [InternetAddress('142.250.190.46', type: InternetAddressType.IPv4)];
            }
            if (host == 'invalid.fail') {
              throw const SocketException('Host not found');
            }
            return [InternetAddress('1.1.1.1', type: InternetAddressType.IPv4)];
          }),
        ],
      );
      addTearDown(container.dispose);
    });

    test('initial state is idle with quick profile', () {
      final state = container.read(portScannerProvider);
      expect(state.status, PortScanStatus.idle);
      expect(state.profile, PortScanProfile.quick);
      expect(state.openPorts, isEmpty);
    });

    test('startScan with empty host sets error', () async {
      final ctrl = container.read(portScannerProvider.notifier);
      await ctrl.startScan('');
      final state = container.read(portScannerProvider);
      expect(state.status, PortScanStatus.failed);
      expect(state.error, contains('Please enter a valid'));
    });

    test('startScan with IPv4 skips DNS and probes ports', () async {
      final ctrl = container.read(portScannerProvider.notifier);
      await ctrl.startScan('192.168.1.1');
      final state = container.read(portScannerProvider);

      expect(state.status, PortScanStatus.done);
      expect(state.activeHost, '192.168.1.1');
      expect(state.resolvedIp, '192.168.1.1');
      expect(state.openPorts, {80, 443});
      expect(state.recentHosts.length, 1);
      expect(state.recentHosts.first.host, '192.168.1.1');
    });

    test('startScan with domain resolves DNS then probes ports', () async {
      final ctrl = container.read(portScannerProvider.notifier);
      await ctrl.startScan('google.com');
      final state = container.read(portScannerProvider);

      expect(state.status, PortScanStatus.done);
      expect(state.activeHost, 'google.com');
      expect(state.resolvedIp, '142.250.190.46');
      expect(state.openPorts, {80, 443});
    });

    test('startScan with unresolvable domain reports DNS failure', () async {
      final ctrl = container.read(portScannerProvider.notifier);
      await ctrl.startScan('invalid.fail');
      final state = container.read(portScannerProvider);

      expect(state.status, PortScanStatus.failed);
      expect(state.error, contains('Could not resolve host'));
    });

    test('clearing and deleting recent hosts', () async {
      final ctrl = container.read(portScannerProvider.notifier);
      await ctrl.startScan('192.168.1.1');
      await ctrl.startScan('192.168.1.2');
      expect(container.read(portScannerProvider).recentHosts.length, 2);

      await ctrl.removeRecentHost('192.168.1.1');
      expect(container.read(portScannerProvider).recentHosts.length, 1);
      expect(container.read(portScannerProvider).recentHosts.first.host, '192.168.1.2');

      await ctrl.clearRecentHosts();
      expect(container.read(portScannerProvider).recentHosts, isEmpty);
    });
  });

  group('PortScannerTool widget tests', () {
    late FakeBridge bridge;

    Widget buildTestWidget({LocalStore? store}) {
      bridge = FakeBridge();
      bridge.open = {80, 443};
      final localStore = store ?? memoryStore();

      return ProviderScope(
        overrides: [
          scannerBridgeProvider.overrideWithValue(bridge),
          localStoreProvider.overrideWithValue(localStore),
          dnsLookupProvider.overrideWithValue((host) async => [
                InternetAddress('93.184.216.34', type: InternetAddressType.IPv4),
              ]),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.dark(),
          home: const Scaffold(body: PortScannerTool()),
        ),
      );
    }

    testWidgets('renders header, input, popular targets, and empty recent hosts', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      expect(find.text('Find open ports'), findsOneWidget);
      expect(find.text('SETTINGS'), findsOneWidget);
      expect(find.text('Enter IP or domain'), findsOneWidget);
      expect(find.text('Popular targets'), findsOneWidget);
      expect(find.text('google.com'), findsOneWidget);
      expect(find.text('Recent hosts'), findsOneWidget);
      expect(find.textContaining('There is no recent host or domain to show'), findsOneWidget);
    });

    testWidgets('tapping popular target triggers scan and displays results', (tester) async {
      await tester.pumpWidget(buildTestWidget());
      await tester.pumpAndSettle();

      // Tap on google.com popular target chip
      await tester.tap(find.text('google.com'));
      await tester.pumpAndSettle();

      // Verify results panel appeared with open ports (PdPanel uppercases its title)
      expect(find.textContaining('SCAN RESULTS: GOOGLE.COM'), findsOneWidget);
      expect(find.text('80'), findsOneWidget);
      expect(find.text('HTTP'), findsOneWidget);
      expect(find.text('443'), findsOneWidget);
      expect(find.text('HTTPS'), findsOneWidget);
      expect(find.text('COPY REPORT'), findsOneWidget);
      expect(find.text('SCAN AGAIN'), findsOneWidget);
    });

    testWidgets('Tools hub shows Port Scanner tool card and opens tool', (tester) async {
      bridge = FakeBridge();
      final store = memoryStore();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            scannerBridgeProvider.overrideWithValue(bridge),
            localStoreProvider.overrideWithValue(store),
          ],
          child: MaterialApp(
            theme: PingDuckTheme.dark(),
            home: const Scaffold(body: ToolsScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Port Scanner'), findsOneWidget);
      expect(find.text('ready'), findsOneWidget);

      await tester.tap(find.text('Port Scanner'));
      await tester.pumpAndSettle();

      expect(find.text('Find open ports'), findsOneWidget);
    });
  });
}
