import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/scanner_bridge.dart';
import '../../../core/network/network_context.dart';
import '../domain/discovered_device.dart';

enum ScanPhase { idle, scanning, done, cancelled, failed }

class ScanState {
  const ScanState({
    this.phase = ScanPhase.idle,
    this.devices = const {},
    this.failure,
    this.startedAt,
    this.finishedAt,
  });

  final ScanPhase phase;

  /// Keyed by IP: the core reports every update as a full record per IP.
  final Map<String, DiscoveredDevice> devices;
  final ScanFailure? failure;
  final DateTime? startedAt;
  final DateTime? finishedAt;

  bool get isScanning => phase == ScanPhase.scanning;

  /// Online devices first, then by IP numerically.
  List<DiscoveredDevice> get sortedDevices {
    final list = devices.values.toList()
      ..sort((a, b) {
        if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
        return _ipKey(a.ip).compareTo(_ipKey(b.ip));
      });
    return list;
  }

  static int _ipKey(String ip) =>
      ip.split('.').fold(0, (acc, p) => (acc << 8) | (int.tryParse(p) ?? 0));

  ScanState copyWith({
    ScanPhase? phase,
    Map<String, DiscoveredDevice>? devices,
    ScanFailure? failure,
    bool clearFailure = false,
    DateTime? startedAt,
    DateTime? finishedAt,
  }) =>
      ScanState(
        phase: phase ?? this.phase,
        devices: devices ?? this.devices,
        failure: clearFailure ? null : failure ?? this.failure,
        startedAt: startedAt ?? this.startedAt,
        finishedAt: finishedAt ?? this.finishedAt,
      );
}

final scannerBridgeProvider = Provider<ScannerBridge>((ref) => FfiScannerBridge());
final multicastLockProvider = Provider<MulticastLock>((ref) => const MulticastLock());

final scanControllerProvider = NotifierProvider<ScanController, ScanState>(ScanController.new);

/// Runs scans and keeps the device inventory. Devices from earlier scans stay
/// listed but go offline until they answer again (Phase 3 adds the cache).
class ScanController extends Notifier<ScanState> {
  @override
  ScanState build() => const ScanState();

  ScannerBridge get _bridge => ref.read(scannerBridgeProvider);

  Future<void> scan({Duration timeout = const Duration(seconds: 3)}) async {
    if (state.isScanning) return;
    final lock = ref.read(multicastLockProvider);
    state = state.copyWith(
      phase: ScanPhase.scanning,
      devices: {for (final e in state.devices.entries) e.key: e.value.offline()},
      clearFailure: true,
      startedAt: DateTime.now(),
    );

    var lockHeld = false;
    try {
      await lock.acquire();
      lockHeld = true;
    } catch (_) {
      // Unicast discovery still works without it.
    }

    try {
      final run = _bridge.scan(timeout: timeout);
      await for (final device in run.devices) {
        if (!ref.mounted) return;
        _upsert(device);
      }
      final summary = await run.done;
      if (!ref.mounted) return;
      state = state.copyWith(
        phase: summary.cancelled ? ScanPhase.cancelled : ScanPhase.done,
        finishedAt: DateTime.now(),
      );
    } on ScanFailure catch (f) {
      if (!ref.mounted) return;
      state = state.copyWith(phase: ScanPhase.failed, failure: f, finishedAt: DateTime.now());
    } finally {
      if (lockHeld) unawaited(lock.release().catchError((_) {}));
    }
  }

  void cancel() {
    if (state.isScanning) _bridge.cancel();
  }

  /// Merging (rather than replacing) keeps what earlier scans learned, so a
  /// name found by last scan's DNS pass does not blink out while this scan's
  /// first ICMP-only report arrives.
  void _upsert(DiscoveredDevice fresh) {
    final previous = state.devices[fresh.ip];
    state = state.copyWith(devices: {...state.devices, fresh.ip: previous?.merge(fresh) ?? fresh});
  }
}
