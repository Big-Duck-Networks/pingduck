import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/network/network_context.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/agent/application/agent_status.dart';
import 'package:pingduck_app/features/agent/domain/agent_unit.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/features/settings/presentation/privacy_settings_screen.dart';
import 'package:pingduck_app/features/settings/presentation/settings_screen.dart';
import 'package:pingduck_app/features/subscription/presentation/paywall_screen.dart';
import 'package:pingduck_app/services/analytics.dart';
import 'package:pingduck_app/services/billing.dart';
import 'package:pingduck_app/services/plan.dart';
import 'package:pingduck_app/services/push_alerts.dart';

import 'fakes.dart';

void main() {
  test('crash reporting defaults to enabled and persists opt-out', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final analytics = FakeAnalytics();

    expect(await isCrashReportingEnabled(store), isTrue);

    await setCrashReportingEnabled(store, analytics, false);
    expect(await isCrashReportingEnabled(store), isFalse);
    expect(analytics.enabled, isFalse);

    await setCrashReportingEnabled(store, analytics, true);
    expect(await isCrashReportingEnabled(store), isTrue);
    expect(analytics.enabled, isTrue);
  });

  test('sanitizeAnalyticsProperties strips network and PII keys', () {
    final cleaned = sanitizeAnalyticsProperties({
      'automatic': false,
      'device_count': 12,
      'ip': '192.168.1.10',
      'MAC': 'AA:BB:CC:DD:EE:FF',
      'hostname': 'living-room-tv',
      'SSID': 'HomeWiFi',
      'bssid': '00:11:22:33:44:55',
      'gateway': '192.168.1.1',
      'cidr': '192.168.1.0/24',
      'devices': ['192.168.1.10'],
      'email': 'user@example.com',
    });

    expect(cleaned, {'automatic': false, 'device_count': 12});
    expect(
      sanitizeAnalyticsProperties({'ip': '10.0.0.1', 'ssid': 'SecretNet'}),
      isNull,
    );
  });

  testWidgets('PrivacySettingsScreen switch toggles analytics opt-out at runtime', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);
    final analytics = FakeAnalytics();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          analyticsProvider.overrideWithValue(analytics),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const PrivacySettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final switchFinder = find.byKey(const Key('crash_reporting_switch'));
    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(analytics.enabled, isTrue);

    // Opt out
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isFalse);
    expect(analytics.enabled, isFalse);
    expect(await isCrashReportingEnabled(store), isFalse);

    // Opt back in
    await tester.tap(switchFinder);
    await tester.pumpAndSettle();

    expect(tester.widget<Switch>(switchFinder).value, isTrue);
    expect(analytics.enabled, isTrue);
    expect(await isCrashReportingEnabled(store), isTrue);
  });

  testWidgets('App settings links to Privacy settings and reflects opt-out state', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);
    final analytics = FakeAnalytics();
    final alerts = FakePushAlerts();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          analyticsProvider.overrideWithValue(analytics),
          pushAlertsProvider.overrideWithValue(alerts),
          planRepositoryProvider.overrideWithValue(FakePlanRepository([Plan.free])),
          myAgentsProvider.overrideWith((_) async => const <PairedAgent>[]),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('Privacy settings'), 200);
    await tester.pumpAndSettle();
    expect(find.text('Privacy settings'), findsOneWidget);
    expect(find.textContaining('Crash reporting on'), findsOneWidget);

    await tester.tap(find.text('Privacy settings'));
    await tester.pumpAndSettle();

    expect(find.text('Analytics Settings'), findsOneWidget);
    await tester.tap(find.byKey(const Key('crash_reporting_switch')));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();

    expect(find.textContaining('Crash reporting off'), findsOneWidget);
  });

  test('ScanController captures scan started and finished without network PII', () async {
    final store = memoryStore();
    addTearDown(store.close);
    final bridge = FakeBridge();
    final quota = FakeQuota();
    final analytics = FakeAnalytics();

    final container = ProviderContainer(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        scannerBridgeProvider.overrideWithValue(bridge),
        scanQuotaProvider.overrideWithValue(quota),
        analyticsProvider.overrideWithValue(analytics),
        multicastLockProvider.overrideWithValue(FakeLock()),
        wifiNameAccessProvider.overrideWithValue(
          WifiNameAccess(wasAsked: () async => true, markAsked: () async {}),
        ),
      ],
    );
    addTearDown(container.dispose);

    final scanFuture = container.read(scanControllerProvider.notifier).scan();
    await pumpEventQueue();

    bridge.devices!.add(
      DiscoveredDevice(
        ip: '10.42.0.1',
        mac: 'AA:BB:CC:DD:EE:01',
        hostname: 'router.local',
        vendor: 'Ubiquiti',
        rttMs: 2,
        sources: const {DiscoverySource.icmp},
        lastSeen: DateTime.utc(2026, 11, 2),
      ),
    );
    await pumpEventQueue();
    await bridge.finish(count: 1);
    await scanFuture;

    expect(analytics.events, [
      {
        'event': 'scan started',
        'properties': {'automatic': false},
      },
      {
        'event': 'scan finished',
        'properties': {
          'automatic': false,
          'cancelled': false,
          'device_count': 1,
        },
      },
    ]);

    // When opted out, no events are captured.
    analytics.events.clear();
    await analytics.setEnabled(false);
    final scanFuture2 = container.read(scanControllerProvider.notifier).scan(automatic: true);
    await pumpEventQueue();
    await bridge.finish(count: 1);
    await scanFuture2;
    expect(analytics.events, isEmpty);
  });

  testWidgets('PaywallScreen captures paywall viewed event', (tester) async {
    final analytics = FakeAnalytics();
    final billing = FakeBilling();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          analyticsProvider.overrideWithValue(analytics),
          billingProvider.overrideWithValue(billing),
          planRepositoryProvider.overrideWithValue(FakePlanRepository([Plan.free])),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const PaywallScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(analytics.events, [
      {'event': 'paywall viewed'},
    ]);
  });
}

