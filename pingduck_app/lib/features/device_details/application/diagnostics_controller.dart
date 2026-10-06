import 'dart:async';
import 'dart:math' as math;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/scanner_bridge.dart';
import '../../scanner/application/scan_controller.dart';

/// Well-known ports with what they usually are and whether exposing them on
/// a LAN deserves a second look.
class PortInfo {
  const PortInfo(this.port, this.service, {this.risk});
  final int port;
  final String service;

  /// Why an open port is worth attention, or null when it is routine.
  final String? risk;
}

const commonPorts = [
  PortInfo(21, 'FTP', risk: 'Plaintext logins'),
  PortInfo(22, 'SSH'),
  PortInfo(23, 'Telnet', risk: 'Plaintext remote shell'),
  PortInfo(53, 'DNS'),
  PortInfo(80, 'HTTP'),
  PortInfo(139, 'NetBIOS', risk: 'Legacy file sharing'),
  PortInfo(443, 'HTTPS'),
  PortInfo(445, 'SMB', risk: 'File sharing; keep off untrusted networks'),
  PortInfo(554, 'RTSP', risk: 'Camera streams are often unauthenticated'),
  PortInfo(631, 'IPP'),
  PortInfo(1883, 'MQTT', risk: 'Often unauthenticated'),
  PortInfo(3389, 'RDP', risk: 'Remote desktop; a common attack target'),
  PortInfo(5000, 'UPnP / DSM'),
  PortInfo(5900, 'VNC', risk: 'Remote desktop; often weakly protected'),
  PortInfo(8008, 'Cast'),
  PortInfo(8080, 'HTTP-alt'),
  PortInfo(8443, 'HTTPS-alt'),
  PortInfo(9100, 'Raw print'),
];

PortInfo portInfo(int port) =>
    commonPorts.firstWhere((p) => p.port == port, orElse: () => PortInfo(port, 'TCP'));

enum PortScanState { idle, running, done, failed }

class DiagnosticsState {
  const DiagnosticsState({
    this.pings = const [],
    this.pingRunning = false,
    this.portScan = PortScanState.idle,
    this.scannedPorts = const [],
    this.openPorts = const {},
    this.wolSentAt,
    this.error,
  });

  /// Ping results oldest first; null entries are timeouts.
  final List<int?> pings;
  final bool pingRunning;
  final PortScanState portScan;
  final List<int> scannedPorts;
  final Set<int> openPorts;
  final DateTime? wolSentAt;
  final String? error;

  List<int> get replies => pings.whereType<int>().toList();
  int? get minRtt => replies.isEmpty ? null : replies.reduce(math.min);
  int? get maxRtt => replies.isEmpty ? null : replies.reduce(math.max);
  double? get avgRtt => replies.isEmpty ? null : replies.reduce((a, b) => a + b) / replies.length;

  /// Mean absolute difference between consecutive replies.
  double? get jitter {
    final r = replies;
    if (r.length < 2) return null;
    var sum = 0;
    for (var i = 1; i < r.length; i++) {
      sum += (r[i] - r[i - 1]).abs();
    }
    return sum / (r.length - 1);
  }

  double get lossPercent => pings.isEmpty ? 0 : 100 * (pings.length - replies.length) / pings.length;

  DiagnosticsState copyWith({
    List<int?>? pings,
    bool? pingRunning,
    PortScanState? portScan,
    List<int>? scannedPorts,
    Set<int>? openPorts,
    DateTime? wolSentAt,
    String? error,
    bool clearError = false,
  }) =>
      DiagnosticsState(
        pings: pings ?? this.pings,
        pingRunning: pingRunning ?? this.pingRunning,
        portScan: portScan ?? this.portScan,
        scannedPorts: scannedPorts ?? this.scannedPorts,
        openPorts: openPorts ?? this.openPorts,
        wolSentAt: wolSentAt ?? this.wolSentAt,
        error: clearError ? null : error ?? this.error,
      );
}

final diagnosticsProvider =
    NotifierProvider.autoDispose.family<DiagnosticsController, DiagnosticsState, String>(DiagnosticsController.new);

/// Live diagnostics for one host. Stops pinging when nothing watches it.
class DiagnosticsController extends Notifier<DiagnosticsState> {
  DiagnosticsController(this.ip);

  final String ip;
  static const window = 60;
  Timer? _timer;
  bool _pingInFlight = false;

  @override
  DiagnosticsState build() {
    ref.onDispose(() => _timer?.cancel());
    return const DiagnosticsState();
  }

  ScannerBridge get _bridge => ref.read(scannerBridgeProvider);

  void startPing({Duration interval = const Duration(seconds: 1)}) {
    if (state.pingRunning) return;
    state = state.copyWith(pingRunning: true, clearError: true);
    _pingOnce();
    _timer = Timer.periodic(interval, (_) => _pingOnce());
  }

  void stopPing() {
    _timer?.cancel();
    _timer = null;
    if (ref.mounted) state = state.copyWith(pingRunning: false);
  }

  void togglePing() => state.pingRunning ? stopPing() : startPing();

  Future<void> _pingOnce() async {
    if (_pingInFlight) return;
    _pingInFlight = true;
    try {
      final rtt = await _bridge.ping(ip);
      if (!ref.mounted || !state.pingRunning) return;
      final next = [...state.pings, rtt];
      state = state.copyWith(pings: next.length > window ? next.sublist(next.length - window) : next);
    } on ScanFailure catch (e) {
      if (ref.mounted) state = state.copyWith(error: e.message);
      stopPing();
    } finally {
      _pingInFlight = false;
    }
  }

  /// Quick scan of [commonPorts], or every port 1-1024 when [deep].
  Future<void> scanPorts({bool deep = false}) async {
    if (state.portScan == PortScanState.running) return;
    final ports = deep ? [for (var p = 1; p <= 1024; p++) p] : [for (final p in commonPorts) p.port];
    state = state.copyWith(portScan: PortScanState.running, scannedPorts: ports, openPorts: {}, clearError: true);
    try {
      final open = await _bridge.openPorts(ip, ports);
      if (!ref.mounted) return;
      state = state.copyWith(portScan: PortScanState.done, openPorts: open);
    } on ScanFailure catch (e) {
      if (ref.mounted) state = state.copyWith(portScan: PortScanState.failed, error: e.message);
    }
  }

  Future<void> wake(String mac, {String? broadcast}) async {
    try {
      await _bridge.wakeOnLan(mac, broadcast: broadcast);
      if (ref.mounted) state = state.copyWith(wolSentAt: DateTime.now(), clearError: true);
    } on ScanFailure catch (e) {
      if (ref.mounted) state = state.copyWith(error: e.message);
    }
  }
}

/// The device the Inspector tab shows; set from the ledger or topology.
final selectedDeviceProvider = NotifierProvider<SelectedDevice, String?>(SelectedDevice.new);

class SelectedDevice extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String? ip) => state = ip;
}
