import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/scanner_bridge.dart';
import '../../../core/network/network_context.dart';
import '../../../services/local_storage.dart';
import '../../../services/scan_quota.dart';
import '../../auth/session.dart';
import '../domain/device_kind.dart';
import '../domain/discovered_device.dart';

enum ScanPhase { idle, scanning, done, cancelled, failed }

class ScanState {
  const ScanState({
    this.phase = ScanPhase.idle,
    this.devices = const {},
    this.lan,
    this.networkId,
    this.networkName,
    this.failure,
    this.startedAt,
    this.finishedAt,
    this.lastScanAt,
  });

  final ScanPhase phase;

  /// Keyed by IP: the core reports every update as a full record per IP.
  final Map<String, DiscoveredDevice> devices;
  final LanInfo? lan;
  final int? networkId;

  /// Wi-Fi name of the network on screen: live from the OS, or remembered
  /// from an earlier scan.
  final String? networkName;
  final ScanFailure? failure;

  /// Title for the device list: the Wi-Fi name, else the subnet.
  String get networkTitle => networkName ?? lan?.cidr ?? 'This network';
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final DateTime? lastScanAt;

  bool get isScanning => phase == ScanPhase.scanning;
  int get onlineCount => devices.values.where((d) => d.isOnline).length;

  Duration? get lastDuration =>
      startedAt != null && finishedAt != null && !isScanning ? finishedAt!.difference(startedAt!) : null;

  /// Online devices this scan found through [source].
  int countBy(DiscoverySource source) => devices.values.where((d) => d.isOnline && d.sources.contains(source)).length;

  DeviceKind kindOf(DiscoveredDevice d) => DeviceKind.of(d, gatewayIp: lan?.gateway);

  /// Online devices first, then by IP numerically.
  List<DiscoveredDevice> get sortedDevices {
    final list = devices.values.toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return ipKey(a.ip).compareTo(ipKey(b.ip));
      });
    return list;
  }

  static int ipKey(String ip) => ip.split('.').fold(0, (acc, p) => (acc << 8) | (int.tryParse(p) ?? 0));

  ScanState copyWith({
    ScanPhase? phase,
    Map<String, DiscoveredDevice>? devices,
    LanInfo? lan,
    int? networkId,
    String? networkName,
    bool clearNetworkName = false,
    ScanFailure? failure,
    bool clearFailure = false,
    DateTime? startedAt,
    DateTime? finishedAt,
    DateTime? lastScanAt,
  }) =>
      ScanState(
        phase: phase ?? this.phase,
        devices: devices ?? this.devices,
        lan: lan ?? this.lan,
        networkId: networkId ?? this.networkId,
        networkName: clearNetworkName ? null : networkName ?? this.networkName,
        failure: clearFailure ? null : failure ?? this.failure,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
        lastScanAt: lastScanAt ?? this.lastScanAt,
      );
}

final scannerBridgeProvider = Provider<ScannerBridge>((ref) => FfiScannerBridge());
final multicastLockProvider = Provider<MulticastLock>((ref) => const MulticastLock());

final scanQuotaProvider = Provider<ScanQuota>((ref) => ServerScanQuota(ref.read(localStoreProvider), () async {
      final result = await (await signedInClient()).rpc('claim_scan');
      return Map<String, dynamic>.from(result as Map);
    }));

/// One-time location prompt that reveals the Wi-Fi name (see [WifiNameAccess]).
final wifiNameAccessProvider = Provider<WifiNameAccess>((ref) {
  final store = ref.read(localStoreProvider);
  return WifiNameAccess(
    wasAsked: () async => await store.setting('askedWifiName') == '1',
    markAsked: () => store.setSetting('askedWifiName', '1'),
  );
});

/// Opened in main() before the first frame.
final localStoreProvider = Provider<LocalStore>((ref) => throw UnimplementedError('override in main()'));

/// What the cache held for the last network, so the first frame is not empty.
final restoredScanProvider = Provider<ScanState>((ref) => const ScanState());

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);

/// Reads the last network's devices from the cache, for [restoredScanProvider].
Future<ScanState> restoreLastScan(LocalStore store) async {
  final id = int.tryParse(await store.setting('lastNetworkId') ?? '');
  if (id == null) return const ScanState();
  final devices = await store.devicesOf(id);
  return ScanState(devices: {for (final d in devices) d.ip: d}, networkId: id, networkName: await store.ssidOf(id));
}

/// Runs scans and keeps the device inventory. Cached devices are shown
/// offline (dimmed) and light up as they answer.
class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => ref.read(restoredScanProvider);

  ScannerBridge get _bridge => ref.read(scannerBridgeProvider);
  LocalStore get _store => ref.read(localStoreProvider);

  /// Without [timeout], uses the Settings choice (`scanTimeoutSec`), else 3s.
  /// [automatic] scans are the ones the app starts itself (launch, Wi-Fi
  /// reconnect): they do not use the daily allowance, but are rate-limited on
  /// Free plans and skipped silently when too soon.
  Future<void> scan({Duration? timeout, bool automatic = false}) async {
    if (state.isScanning) return;
    final before = state;
    state = state.copyWith(phase: ScanPhase.scanning, clearFailure: true, startedAt: DateTime.now());
    timeout ??= Duration(seconds: int.tryParse(await _store.setting('scanTimeoutSec') ?? '') ?? 3);

    await ref.read(wifiNameAccessProvider).ensure();
    final lan = await _bridge.lanInfo();
    if (!ref.mounted) return;
    if (lan == null) {
      state = state.copyWith(
        phase: ScanPhase.failed,
        failure: const ScanFailure(ScanFailureKind.noNetwork, 'Not connected to a local network.'),
        finishedAt: DateTime.now(),
      );
      return;
    }

    // Free plans get a few scans a day. Checked only once a LAN is found, so
    // a scan that could not run does not use one; cached devices stay shown.
    final quota = ref.read(scanQuotaProvider);
    if (automatic) {
      final allowed = await quota.claimAutomatic();
      if (!ref.mounted) return;
      if (!allowed) {
        state = before;
        return;
      }
    } else if (!(await quota.claim()).allowed) {
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: ScanPhase.failed,
        failure: const ScanFailure(ScanFailureKind.quotaExceeded, 'Daily scan limit reached.'),
        finishedAt: DateTime.now(),
      );
      return;
    }

    // Switching networks swaps in that network's cached inventory.
    final networkId = await _store.networkFor(key: lan.key, cidr: lan.cidr, gateway: lan.gateway);
    var devices = state.devices;
    var name = state.networkName;
    if (networkId != state.networkId) {
      devices = {for (final d in await _store.devicesOf(networkId)) d.ip: d};
      name = await _store.ssidOf(networkId);
    }
    if (!ref.mounted) return;
    state = state.copyWith(
      lan: lan,
      networkId: networkId,
      networkName: lan.ssid ?? name,
      clearNetworkName: lan.ssid == null && name == null,
      devices: {for (final e in devices.entries) e.key: e.value.offline()},
    );

    final lock = ref.read(multicastLockProvider);
    var lockHeld = false;
    try {
      await lock.acquire();
      lockHeld = true;
    } catch (_) {
      // Unicast discovery still works without it.
    }

    final sampled = <String>{};
    try {
      final run = _bridge.scan(cidr: lan.cidr, timeout: timeout);
      await for (final device in run.devices) {
        if (!ref.mounted) return;
        _upsert(device, sampled);
      }
      final summary = await run.done;
      if (!ref.mounted) return;
      final now = DateTime.now();
      state = state.copyWith(
        phase: summary.cancelled ? ScanPhase.cancelled : ScanPhase.done,
        finishedAt: now,
        lastScanAt: now,
      );
      await _persist(networkId, now, lan.ssid);
    } on ScanFailure catch (f) {
      if (!ref.mounted) return;
      state = state.copyWith(phase: ScanPhase.failed, failure: f, finishedAt: DateTime.now());
    } finally {
      if (lockHeld) unawaited(lock.release().catchError((_) {}));
    }
  }

  /// Wipes the cached inventory, on disk and on screen.
  /// Forgets a saved network. Forgetting the one on screen empties the list;
  /// the next scan starts it afresh.
  Future<void> forgetNetwork(int networkId) async {
    if (state.isScanning && state.networkId == networkId) return;
    await _store.forgetNetwork(networkId);
    if (ref.mounted && state.networkId == networkId) {
      state = ScanState(lan: state.lan);
    }
  }

  Future<void> clearInventory() async {
    if (state.isScanning) return;
    await _store.clearInventory();
    if (ref.mounted) state = ScanState(lan: state.lan);
  }

  void cancel() {
    if (state.isScanning) _bridge.cancel();
  }

  Future<void> rename(String ip, String? name) => _edit(ip, (d) {
        final n = name?.trim();
        return n == null || n.isEmpty ? d.copyWith(clearCustomName: true) : d.copyWith(customName: n);
      });

  Future<void> setNotes(String ip, String? notes) => _edit(ip, (d) {
        final n = notes?.trim();
        return n == null || n.isEmpty ? d.copyWith(clearNotes: true) : d.copyWith(notes: n);
      });

  /// Removes a device from the inventory and the cache.
  Future<void> forget(String ip) async {
    state = state.copyWith(devices: {...state.devices}..remove(ip));
    final id = state.networkId;
    if (id != null) await _store.forgetDevice(id, ip);
  }

  Future<void> _edit(String ip, DiscoveredDevice Function(DiscoveredDevice) change) async {
    final d = state.devices[ip];
    if (d == null) return;
    final updated = change(d);
    state = state.copyWith(devices: {...state.devices, ip: updated});
    final id = state.networkId;
    if (id != null) await _store.saveDevices(id, [updated]);
  }

  /// Merging (rather than replacing) keeps what earlier scans learned, so a
  /// name found by last scan's DNS pass does not blink out while this scan's
  /// first ICMP-only report arrives. One RTT sample per device per scan.
  void _upsert(DiscoveredDevice fresh, Set<String> sampled) {
    final previous = state.devices[fresh.ip];
    var merged = previous?.merge(fresh) ?? fresh;
    final rtt = fresh.rttMs;
    if (rtt != null && sampled.add(fresh.ip)) merged = merged.withRttSample(rtt);
    state = state.copyWith(devices: {...state.devices, fresh.ip: merged});
  }

  Future<void> _persist(int networkId, DateTime at, String? ssid) async {
    await _store.saveDevices(networkId, state.devices.values);
    await _store.markScanned(networkId, at, ssid: ssid);
    await _store.setSetting('lastNetworkId', '$networkId');
  }
}
