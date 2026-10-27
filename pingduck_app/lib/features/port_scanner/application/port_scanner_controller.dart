import 'dart:async';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/scanner_bridge.dart';
import '../../device_details/application/diagnostics_controller.dart';
import '../../scanner/application/scan_controller.dart';
import '../domain/port_scan_models.dart';

enum PortScanStatus { idle, resolving, scanning, done, failed, cancelled }

class PortScannerState {
  const PortScannerState({
    this.targetInput = '',
    this.activeHost,
    this.resolvedIp,
    this.profile = PortScanProfile.quick,
    this.customPorts = const [],
    this.timeoutMs = 800,
    this.status = PortScanStatus.idle,
    this.openPorts = const {},
    this.scannedPorts = const [],
    this.scanDuration,
    this.error,
    this.recentHosts = const [],
  });

  final String targetInput;
  final String? activeHost;
  final String? resolvedIp;
  final PortScanProfile profile;
  final List<int> customPorts;
  final int timeoutMs;
  final PortScanStatus status;
  final Set<int> openPorts;
  final List<int> scannedPorts;
  final Duration? scanDuration;
  final String? error;
  final List<RecentPortScanHost> recentHosts;

  bool get isScanning => status == PortScanStatus.resolving || status == PortScanStatus.scanning;

  PortScannerState copyWith({
    String? targetInput,
    String? activeHost,
    String? resolvedIp,
    PortScanProfile? profile,
    List<int>? customPorts,
    int? timeoutMs,
    PortScanStatus? status,
    Set<int>? openPorts,
    List<int>? scannedPorts,
    Duration? scanDuration,
    String? error,
    bool clearError = false,
    List<RecentPortScanHost>? recentHosts,
  }) =>
      PortScannerState(
        targetInput: targetInput ?? this.targetInput,
        activeHost: activeHost ?? this.activeHost,
        resolvedIp: resolvedIp ?? this.resolvedIp,
        profile: profile ?? this.profile,
        customPorts: customPorts ?? this.customPorts,
        timeoutMs: timeoutMs ?? this.timeoutMs,
        status: status ?? this.status,
        openPorts: openPorts ?? this.openPorts,
        scannedPorts: scannedPorts ?? this.scannedPorts,
        scanDuration: scanDuration ?? this.scanDuration,
        error: clearError ? null : error ?? this.error,
        recentHosts: recentHosts ?? this.recentHosts,
      );
}

const recentHostsKey = 'recent_port_scan_hosts';

typedef DnsLookupFn = Future<List<InternetAddress>> Function(String host);

/// Injectable DNS resolver for testing without network calls.
final dnsLookupProvider = Provider<DnsLookupFn>((ref) => InternetAddress.lookup);

final portScannerProvider =
    NotifierProvider<PortScannerController, PortScannerState>(PortScannerController.new);

class PortScannerController extends Notifier<PortScannerState> {
  @override
  PortScannerState build() {
    _loadRecentHosts();
    return const PortScannerState();
  }

  ScannerBridge get _bridge => ref.read(scannerBridgeProvider);
  DnsLookupFn get _dns => ref.read(dnsLookupProvider);

  Future<void> _loadRecentHosts() async {
    try {
      final store = ref.read(localStoreProvider);
      final raw = await store.setting(recentHostsKey);
      if (raw != null && raw.isNotEmpty && ref.mounted) {
        final list = RecentPortScanHost.decodeList(raw);
        state = state.copyWith(recentHosts: list);
      }
    } catch (_) {}
  }

  void updateInput(String input) {
    state = state.copyWith(targetInput: input, clearError: true);
  }

  void setProfile(PortScanProfile profile, {List<int>? custom}) {
    state = state.copyWith(
      profile: profile,
      customPorts: custom ?? state.customPorts,
    );
  }

  void setTimeout(int ms) {
    state = state.copyWith(timeoutMs: ms);
  }

  void resetToInput() {
    state = state.copyWith(
      status: PortScanStatus.idle,
      clearError: true,
      openPorts: const {},
      scannedPorts: const [],
      scanDuration: null,
    );
  }

  List<int> resolvePortsToScan() {
    return switch (state.profile) {
      PortScanProfile.quick => [for (final p in commonPorts) p.port],
      PortScanProfile.standard => standardTop100Ports,
      PortScanProfile.deep => [for (var i = 1; i <= 1024; i++) i],
      PortScanProfile.custom => state.customPorts.isNotEmpty
          ? state.customPorts
          : [for (final p in commonPorts) p.port],
    };
  }

  Future<void> startScan([String? explicitHost]) async {
    if (state.isScanning) return;

    final rawTarget = explicitHost ?? state.targetInput;
    final cleaned = cleanHostInput(rawTarget);

    if (cleaned.isEmpty) {
      state = state.copyWith(
        status: PortScanStatus.failed,
        error: 'Please enter a valid IP address or domain.',
      );
      return;
    }

    final ports = resolvePortsToScan();
    state = state.copyWith(
      targetInput: rawTarget,
      activeHost: cleaned,
      resolvedIp: null,
      status: PortScanStatus.resolving,
      scannedPorts: ports,
      openPorts: const {},
      scanDuration: null,
      clearError: true,
    );

    final stopwatch = Stopwatch()..start();

    // 1. Resolve DNS to IPv4 if needed
    String targetIp;
    final isIpv4 = RegExp(r'^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$').hasMatch(cleaned);

    if (isIpv4) {
      targetIp = cleaned;
    } else {
      try {
        final addresses = await _dns(cleaned);
        final ipv4s = addresses.where((a) => a.type == InternetAddressType.IPv4).toList();
        if (ipv4s.isEmpty) {
          throw const SocketException('No IPv4 address found for host');
        }
        targetIp = ipv4s.first.address;
      } catch (e) {
        if (!ref.mounted) return;
        state = state.copyWith(
          status: PortScanStatus.failed,
          error: 'Could not resolve host "$cleaned". Check domain or connection.',
        );
        return;
      }
    }

    if (!ref.mounted) return;
    state = state.copyWith(
      resolvedIp: targetIp,
      status: PortScanStatus.scanning,
    );

    // 2. Perform port probe
    try {
      final open = await _bridge.openPorts(
        targetIp,
        ports,
        timeout: Duration(milliseconds: state.timeoutMs),
      );
      stopwatch.stop();

      if (!ref.mounted) return;

      final updatedState = state.copyWith(
        status: PortScanStatus.done,
        openPorts: open,
        scanDuration: stopwatch.elapsed,
      );
      state = updatedState;

      // 3. Save to recent hosts
      await _recordRecentHost(
        host: cleaned,
        resolvedIp: targetIp,
        openPorts: open.length,
        scannedPorts: ports.length,
        profile: state.profile,
      );
    } on ScanFailure catch (e) {
      stopwatch.stop();
      if (!ref.mounted) return;
      state = state.copyWith(
        status: e.message == 'cancelled' ? PortScanStatus.cancelled : PortScanStatus.failed,
        error: e.message == 'cancelled' ? null : e.message,
        scanDuration: stopwatch.elapsed,
      );
    } catch (e) {
      stopwatch.stop();
      if (!ref.mounted) return;
      state = state.copyWith(
        status: PortScanStatus.failed,
        error: e.toString(),
        scanDuration: stopwatch.elapsed,
      );
    }
  }

  void cancelScan() {
    if (!state.isScanning) return;
    _bridge.cancel();
    state = state.copyWith(status: PortScanStatus.cancelled);
  }

  Future<void> _recordRecentHost({
    required String host,
    required String? resolvedIp,
    required int openPorts,
    required int scannedPorts,
    required PortScanProfile profile,
  }) async {
    final newEntry = RecentPortScanHost(
      host: host,
      resolvedIp: resolvedIp,
      timestamp: DateTime.now(),
      openPortsCount: openPorts,
      scannedPortsCount: scannedPorts,
      profile: profile,
    );

    final filtered = state.recentHosts.where((h) => h.host.toLowerCase() != host.toLowerCase()).toList();
    final updated = [newEntry, ...filtered];
    if (updated.length > 20) {
      updated.removeRange(20, updated.length);
    }

    state = state.copyWith(recentHosts: updated);
    try {
      final store = ref.read(localStoreProvider);
      await store.setSetting(recentHostsKey, RecentPortScanHost.encodeList(updated));
    } catch (_) {}
  }

  Future<void> removeRecentHost(String host) async {
    final updated = state.recentHosts.where((h) => h.host.toLowerCase() != host.toLowerCase()).toList();
    state = state.copyWith(recentHosts: updated);
    try {
      final store = ref.read(localStoreProvider);
      await store.setSetting(recentHostsKey, RecentPortScanHost.encodeList(updated));
    } catch (_) {}
  }

  Future<void> clearRecentHosts() async {
    state = state.copyWith(recentHosts: const []);
    try {
      final store = ref.read(localStoreProvider);
      await store.setSetting(recentHostsKey, '[]');
    } catch (_) {}
  }
}
