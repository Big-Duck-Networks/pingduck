import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/agent/application/agent_status.dart';
import 'package:pingduck_app/features/agent/domain/agent_unit.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/remote_device.dart';
import 'package:pingduck_app/features/settings/presentation/settings_screen.dart';
import 'package:pingduck_app/services/local_storage.dart';
import 'package:pingduck_app/services/push_alerts.dart';
import 'package:pingduck_app/services/supabase_sync.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late FakeSyncRepository repo;
  late FakeAuth auth;
  late FakePushAlerts alerts;

  PairedAgent agent({DateTime? lastSeen, String? version = '0.3.1'}) => PairedAgent(
        id: 'a1',
        networkId: 'remote-1',
        name: 'homelab',
        version: version,
        lastSeenAt: lastSeen,
        createdAt: DateTime(2026),
      );

  Future<void> pump(WidgetTester tester, {List<PairedAgent> agents = const [], bool premium = true}) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    store = memoryStore();
    addTearDown(store.close);
    repo = FakeSyncRepository();
    alerts = FakePushAlerts();
    auth = FakeAuth(accounts: {'me@example.invalid': 'pw'});
    await tester.runAsync(() async {
      final net = await store.networkFor(key: 'k', cidr: '10.42.0.0/24');
      await store.setRemoteId(net, 'remote-1');
      await auth.signIn('me@example.invalid', 'pw');
    });
    repo.rows['remote-1'] = [const RemoteDevice(mac: 'aa:bb:cc:00:00:05', ip: '10.42.0.5')];
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        accountAuthProvider.overrideWithValue(auth),
        myAgentsProvider.overrideWith((ref) async => agents),
        isPremiumProvider.overrideWith((ref) async => premium),
        syncRepositoryProvider.overrideWithValue(repo),
        pushAlertsProvider.overrideWithValue(alerts),
        supabaseSyncProvider.overrideWith(() => SupabaseSync(debounce: Duration.zero)),
      ],
      child: MaterialApp(theme: PingDuckTheme.light(), home: const SettingsScreen()),
    ));
    await tester.pumpAndSettle();
  }

  Switch switchOf(WidgetTester tester, String key) => tester.widget<Switch>(find.byKey(Key(key)));

  testWidgets('without an agent the rows explain what is needed', (tester) async {
    await pump(tester);

    expect(find.text('Not set up · Add a monitoring unit'), findsOneWidget);
    expect(find.text('Needs a monitoring unit'), findsNWidgets(2));
    expect(switchOf(tester, 'cloud_sync_switch').onChanged, isNull);
    expect(switchOf(tester, 'alerts_switch').onChanged, isNull);
    expect(find.byKey(const Key('mark_all_known')), findsNothing);
  });

  testWidgets('a recently seen agent shows online with its version', (tester) async {
    await pump(tester, agents: [agent(lastSeen: DateTime.now().subtract(const Duration(seconds: 30)))]);

    expect(find.text('homelab · Online · v0.3.1'), findsOneWidget);
    expect(switchOf(tester, 'cloud_sync_switch').value, isTrue);
  });

  testWidgets('a quiet agent shows when it was last seen', (tester) async {
    await pump(tester, agents: [agent(lastSeen: DateTime.now().subtract(const Duration(hours: 3)), version: null)]);
    expect(find.text('homelab · Last seen 3 h ago'), findsOneWidget);
  });

  testWidgets('alerts say why they are off', (tester) async {
    await pump(tester, agents: [agent()], premium: false);
    expect(find.text('Premium plan required'), findsOneWidget);
    expect(switchOf(tester, 'alerts_switch').onChanged, isNull);
  });

  testWidgets('alerts can be switched on and off on Android with Premium', (tester) async {
    await pump(tester, agents: [agent()]);
    expect(find.text('Off'), findsOneWidget);

    await tester.tap(find.byKey(const Key('alerts_switch')));
    await tester.pumpAndSettle();
    expect(alerts.calls, ['enable']);
    expect(switchOf(tester, 'alerts_switch').value, isTrue);
    expect(find.text('On · A notification when a device joins'), findsOneWidget);

    await tester.tap(find.byKey(const Key('alerts_switch')));
    await tester.pumpAndSettle();
    expect(alerts.calls, ['enable', 'disable']);
    expect(switchOf(tester, 'alerts_switch').value, isFalse);
  });

  testWidgets('denied notification permission explains where to fix it', (tester) async {
    await pump(tester, agents: [agent()]);
    alerts.deny = true;

    await tester.tap(find.byKey(const Key('alerts_switch')));
    await tester.pumpAndSettle();
    expect(switchOf(tester, 'alerts_switch').value, isFalse);
    expect(find.text('Notifications are off for PingDuck. Turn them on in Android settings.'), findsOneWidget);
  });

  testWidgets('alerts are not offered off Android yet', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await pump(tester, agents: [agent()]);
    expect(find.text('Android only for now'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('cloud sync can be switched off and on', (tester) async {
    await pump(tester, agents: [agent()]);

    await tester.tap(find.byKey(const Key('cloud_sync_switch')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => store.setting(cloudSyncKey)), '0');
    expect(switchOf(tester, 'cloud_sync_switch').value, isFalse);
    expect(find.text('Off · Agent devices stay on the server'), findsOneWidget);

    await tester.tap(find.byKey(const Key('cloud_sync_switch')));
    await tester.pumpAndSettle();
    expect(await tester.runAsync(() => store.setting(cloudSyncKey)), '1');
    expect(repo.fetches, contains('remote-1'));
  });

  testWidgets('mark all known writes the server flag and confirms', (tester) async {
    await pump(tester, agents: [agent()]);

    await tester.ensureVisible(find.byKey(const Key('mark_all_known')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('mark_all_known')));
    // The merge runs a real (in-memory) database transaction.
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
    await tester.pumpAndSettle();

    expect(repo.known[('remote-1', 'aa:bb:cc:00:00:05')], isTrue);
    expect(find.text('Current devices marked as known. Only new ones will alert.'), findsOneWidget);
  });
}
