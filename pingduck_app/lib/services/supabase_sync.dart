import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/account_auth.dart';
import '../features/auth/session.dart';
import '../features/scanner/application/scan_controller.dart';
import '../features/scanner/domain/remote_device.dart';
import 'local_storage.dart';

/// A network the account monitors, as stored in Supabase.
typedef RemoteNetwork = ({String id, String cidr, String? gateway, String? ssid});

/// The agent's devices in Supabase, read with the user's own session (RLS:
/// devices_own_read / devices_own_update).
abstract interface class SyncRepository {
  /// The account's own networks (RLS: networks_own). The phone matches its
  /// network against these itself, so its subnet isn't sent anywhere.
  Future<List<RemoteNetwork>> myNetworks();

  Future<List<RemoteDevice>> devicesOf(String remoteNetworkId);

  /// Emits whenever a device row of the network changes. Cancelling the
  /// subscription closes the Realtime channel.
  Stream<void> changesOf(String remoteNetworkId);

  Future<void> setKnown(String remoteNetworkId, String mac, bool known);

  Future<void> markAllKnown(String remoteNetworkId);
}

class SupabaseSyncRepository implements SyncRepository {
  @override
  Future<List<RemoteNetwork>> myNetworks() async {
    final rows = await (await signedInClient()).from('networks').select('id, cidr, gateway_ip, ssid');
    return [
      for (final r in rows)
        (
          id: r['id'] as String,
          cidr: r['cidr'] as String,
          // inet can come back as "10.0.0.1/32".
          gateway: (r['gateway_ip'] as String?)?.replaceFirst(RegExp(r'/32$'), ''),
          ssid: r['ssid'] as String?,
        ),
    ];
  }

  @override
  Future<List<RemoteDevice>> devicesOf(String remoteNetworkId) async {
    final rows = await (await signedInClient())
        .from('devices')
        .select(RemoteDevice.columns)
        .eq('network_id', remoteNetworkId);
    return [for (final r in rows) ?RemoteDevice.fromRow(r)];
  }

  @override
  Stream<void> changesOf(String remoteNetworkId) {
    late final StreamController<void> out;
    RealtimeChannel? channel;
    out = StreamController<void>(
      onListen: () async {
        final client = await signedInClient();
        channel = client
            .channel('devices:$remoteNetworkId')
            .onPostgresChanges(
              event: PostgresChangeEvent.all,
              schema: 'public',
              table: 'devices',
              filter: PostgresChangeFilter(
                type: PostgresChangeFilterType.eq,
                column: 'network_id',
                value: remoteNetworkId,
              ),
              callback: (_) => out.add(null),
            )
            .subscribe();
      },
      onCancel: () async {
        final c = channel;
        if (c != null) await Supabase.instance.client.removeChannel(c);
      },
    );
    return out.stream;
  }

  @override
  Future<void> setKnown(String remoteNetworkId, String mac, bool known) async => (await signedInClient())
      .from('devices')
      .update({'is_known': known})
      .eq('network_id', remoteNetworkId)
      .eq('mac', mac);

  @override
  Future<void> markAllKnown(String remoteNetworkId) async =>
      (await signedInClient()).from('devices').update({'is_known': true}).eq('network_id', remoteNetworkId);
}

enum SyncPhase {
  /// Cloud sync is switched off, or there is nothing to sync (anonymous, or
  /// no network with a monitoring unit).
  off,
  syncing,

  /// Fetched and subscribed to changes.
  live,
  failed,
}

class SyncStatus {
  const SyncStatus(this.phase, {this.lastSyncedAt});
  final SyncPhase phase;
  final DateTime? lastSyncedAt;
}

/// Local setting; anything but '0' means on.
const cloudSyncKey = 'cloud_sync';

/// Keeps the cache in step with the agent: fetches each linked network's
/// devices, then re-fetches whenever Realtime reports a change. Re-fetching
/// the whole network (a few hundred rows at most) is simpler than applying
/// row payloads and heals any missed event.
class SupabaseSync extends Notifier<SyncStatus> {
  SupabaseSync({this.debounce = const Duration(seconds: 2)});

  /// An agent sync writes every device in one transaction, which arrives as
  /// a burst of change events; one re-fetch covers them all.
  final Duration debounce;

  final _subscriptions = <StreamSubscription<void>>[];
  final _timers = <String, Timer>{};

  /// Bumped by every start/stop, so an older start that is still awaiting
  /// gives up instead of subscribing twice.
  int _run = 0;

  @override
  SyncStatus build() {
    ref.onDispose(_close);
    return const SyncStatus(SyncPhase.off);
  }

  LocalStore get _store => ref.read(localStoreProvider);
  SyncRepository get _repo => ref.read(syncRepositoryProvider);

  /// (Re)starts syncing. Safe to call repeatedly: on launch, after pairing,
  /// when the app comes back to the foreground (Realtime sockets don't
  /// survive the background) and when the setting is switched on.
  Future<void> start() async {
    final run = ++_run;
    bool current() => ref.mounted && run == _run;
    await _close();
    if (ref.read(accountAuthProvider).email == null || await _store.setting(cloudSyncKey) == '0') {
      if (current()) state = SyncStatus(SyncPhase.off, lastSyncedAt: state.lastSyncedAt);
      return;
    }
    await _autoLink();
    if (!current()) return;
    final linked = await _store.linkedNetworks();
    if (!current()) return;
    if (linked.isEmpty) {
      state = SyncStatus(SyncPhase.off, lastSyncedAt: state.lastSyncedAt);
      return;
    }
    state = SyncStatus(SyncPhase.syncing, lastSyncedAt: state.lastSyncedAt);
    try {
      for (final n in linked) {
        await _pull(n.id, n.remoteId);
        if (!current()) return;
        _subscriptions.add(_repo.changesOf(n.remoteId).listen(
              (_) => _schedulePull(n.id, n.remoteId),
              onError: (Object e) => _fail(e),
            ));
      }
      state = SyncStatus(SyncPhase.live, lastSyncedAt: DateTime.now());
    } catch (e) {
      if (current()) _fail(e);
    }
  }

  Future<void> stop() async {
    _run++;
    await _close();
    if (ref.mounted) state = SyncStatus(SyncPhase.off, lastSyncedAt: state.lastSyncedAt);
  }

  /// Fetches once more now, e.g. when an alert arrives in the foreground.
  Future<void> refresh() async {
    for (final n in await _store.linkedNetworks()) {
      await _pull(n.id, n.remoteId);
    }
  }

  /// Marks the device with [mac] known (no alerts) or not, on the server
  /// first, so a failure leaves the cache untouched. Throws when the network
  /// isn't linked to Supabase or the server refuses.
  Future<void> setKnown(int networkId, String mac, bool known) async {
    final remoteId = await _store.remoteIdOf(networkId);
    if (remoteId == null) throw StateError('network $networkId has no monitoring unit');
    await _repo.setKnown(remoteId, mac, known);
    await _store.setKnown(networkId, mac, known);
    if (ref.mounted) await ref.read(scanControllerProvider.notifier).reloadFromCache(networkId);
  }

  /// Marks every device the agents have reported as known, e.g. right after
  /// pairing, so only devices that join later raise alerts.
  Future<void> markAllKnown() async {
    for (final n in await _store.linkedNetworks()) {
      await _repo.markAllKnown(n.remoteId);
      await _pull(n.id, n.remoteId);
    }
  }

  /// Links local networks to the account's monitored network with the same
  /// subnet and gateway, so a second phone (or one that paired from Windows)
  /// syncs without pairing again. The Wi-Fi name settles a tie; a match that
  /// is still ambiguous is left unlinked rather than guessed.
  Future<void> _autoLink() async {
    final unlinked = await _store.unlinkedNetworks();
    if (unlinked.isEmpty) return;
    final List<RemoteNetwork> mine;
    try {
      mine = await _repo.myNetworks();
    } catch (e) {
      debugPrint('cloud sync: auto-link: $e');
      return;
    }
    for (final n in unlinked) {
      var match = [for (final r in mine) if (r.cidr == n.cidr && r.gateway == n.gateway) r];
      if (match.length > 1 && n.ssid != null) match = [for (final r in match) if (r.ssid == n.ssid) r];
      if (match.length == 1) await _store.setRemoteId(n.id, match.single.id);
    }
  }

  void _schedulePull(int networkId, String remoteId) {
    _timers[remoteId]?.cancel();
    _timers[remoteId] = Timer(debounce, () async {
      try {
        await _pull(networkId, remoteId);
        if (ref.mounted) state = SyncStatus(SyncPhase.live, lastSyncedAt: DateTime.now());
      } catch (e) {
        _fail(e);
      }
    });
  }

  Future<void> _pull(int networkId, String remoteId) async {
    final remote = await _repo.devicesOf(remoteId);
    await _store.mergeRemoteDevices(networkId, remote);
    if (!ref.mounted) return;
    await ref.read(scanControllerProvider.notifier).reloadFromCache(networkId);
  }

  void _fail(Object e) {
    debugPrint('cloud sync: $e');
    if (ref.mounted) state = SyncStatus(SyncPhase.failed, lastSyncedAt: state.lastSyncedAt);
  }

  Future<void> _close() async {
    for (final t in _timers.values) {
      t.cancel();
    }
    _timers.clear();
    final subs = [..._subscriptions];
    _subscriptions.clear();
    for (final s in subs) {
      await s.cancel();
    }
  }
}

/// The Supabase network id of a local network, or null when it has no
/// monitoring unit (so nothing about it is on the server).
final linkedRemoteIdProvider = FutureProvider.family<String?, int>(
  (ref, networkId) => ref.read(localStoreProvider).remoteIdOf(networkId),
);

final syncRepositoryProvider = Provider<SyncRepository>((ref) => SupabaseSyncRepository());

final supabaseSyncProvider = NotifierProvider<SupabaseSync, SyncStatus>(SupabaseSync.new);
