import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/features/scanner/domain/remote_device.dart';
import 'package:pingduck_app/services/local_storage.dart';
import 'package:pingduck_app/services/supabase_sync.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late FakeSyncRepository repo;
  late FakeAuth auth;
  late ProviderContainer container;
  late int net;

  ProviderContainer make(ScanState restored) => ProviderContainer(overrides: [
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(restored),
        accountAuthProvider.overrideWithValue(auth),
        syncRepositoryProvider.overrideWithValue(repo),
        supabaseSyncProvider.overrideWith(() => SupabaseSync(debounce: Duration.zero)),
      ]);

  setUp(() async {
    store = memoryStore();
    repo = FakeSyncRepository();
    auth = FakeAuth(accounts: {'me@example.invalid': 'pw'});
    net = await store.networkFor(key: 'k', cidr: '10.42.0.0/24', gateway: '10.42.0.1');
    await store.setRemoteId(net, 'remote-1');
    await store.setSetting('lastNetworkId', '$net');
    repo.rows['remote-1'] = [const RemoteDevice(mac: 'aa:bb:cc:00:00:05', ip: '10.42.0.5', vendor: 'Synology')];
    container = make(await restoreLastScan(store));
  });
  tearDown(() async {
    container.dispose();
    await store.close();
  });

  SupabaseSync sync() => container.read(supabaseSyncProvider.notifier);
  SyncPhase phase() => container.read(supabaseSyncProvider).phase;

  test('signed in: fetches, merges, shows on screen and subscribes', () async {
    await auth.signIn('me@example.invalid', 'pw');
    await sync().start();

    expect(phase(), SyncPhase.live);
    expect(repo.fetches, ['remote-1']);
    expect(repo.listening, ['remote-1']);
    final shown = container.read(scanControllerProvider).devices['10.42.0.5'];
    expect(shown?.vendor, 'Synology');
    expect(shown?.sources, {DiscoverySource.agent});
  });

  test('a change re-fetches the network', () async {
    await auth.signIn('me@example.invalid', 'pw');
    await sync().start();
    repo.rows['remote-1'] = [
      ...repo.rows['remote-1']!,
      const RemoteDevice(mac: 'aa:bb:cc:00:00:06', ip: '10.42.0.6', hostname: 'new-thing'),
    ];

    repo.change('remote-1');
    await pumpEventQueue();

    expect(repo.fetches, ['remote-1', 'remote-1']);
    expect(container.read(scanControllerProvider).devices['10.42.0.6']?.hostname, 'new-thing');
  });

  test('anonymous installs do not sync', () async {
    await sync().start();
    expect(phase(), SyncPhase.off);
    expect(repo.fetches, isEmpty);
  });

  test('switched off: nothing is fetched or subscribed', () async {
    await auth.signIn('me@example.invalid', 'pw');
    await store.setSetting(cloudSyncKey, '0');
    await sync().start();
    expect(phase(), SyncPhase.off);
    expect(repo.fetches, isEmpty);
    expect(repo.listening, isEmpty);
  });

  test('stop closes the subscription; overlapping starts subscribe once', () async {
    await auth.signIn('me@example.invalid', 'pw');
    await Future.wait([sync().start(), sync().start()]);
    expect(repo.listening, ['remote-1']);

    await sync().stop();
    expect(repo.listening, isEmpty);
    expect(phase(), SyncPhase.off);
  });

  test('a live scan keeps its online state when sync lands', () async {
    container.dispose();
    container = make(ScanState(
      networkId: net,
      devices: {'10.42.0.5': const DiscoveredDevice(ip: '10.42.0.5', isOnline: true, rttMs: 4)},
    ));
    await auth.signIn('me@example.invalid', 'pw');
    await sync().start();

    final d = container.read(scanControllerProvider).devices['10.42.0.5']!;
    expect(d.isOnline, isTrue);
    expect(d.rttMs, 4);
    expect(d.mac, 'aa:bb:cc:00:00:05');
  });

  test('setKnown writes the server first, then the cache and the screen', () async {
    await auth.signIn('me@example.invalid', 'pw');
    await sync().start();

    await sync().setKnown(net, 'aa:bb:cc:00:00:05', true);

    expect(repo.known[('remote-1', 'aa:bb:cc:00:00:05')], isTrue);
    expect(container.read(scanControllerProvider).devices['10.42.0.5']?.isKnown, isTrue);
  });

  test('setKnown on a network without a monitoring unit fails and changes nothing', () async {
    final other = await store.networkFor(key: 'k2', cidr: '192.168.1.0/24');
    await expectLater(sync().setKnown(other, 'aa:bb:cc:00:00:09', true), throwsStateError);
    expect(repo.known, isEmpty);
  });

  test('markAllKnown flags every reported device', () async {
    await auth.signIn('me@example.invalid', 'pw');
    await sync().markAllKnown();
    expect(repo.known, {('remote-1', 'aa:bb:cc:00:00:05'): true});
  });
}
