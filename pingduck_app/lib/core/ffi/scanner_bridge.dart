import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pingduck_core/pingduck_core.dart';

import '../../features/scanner/domain/discovered_device.dart';
import '../network/network_context.dart';

/// Why a scan could not run.
/// [quotaExceeded] and [quotaUnverified] come from the app's plan check, not
/// the core.
enum ScanFailureKind { noNetwork, permission, quotaExceeded, quotaUnverified, other }

class ScanFailure implements Exception {
  const ScanFailure(this.kind, this.message);
  final ScanFailureKind kind;
  final String message;

  @override
  String toString() => 'ScanFailure($kind): $message';
}

class ScanSummary {
  const ScanSummary({required this.deviceCount, required this.cancelled});
  final int deviceCount;
  final bool cancelled;
}

/// One running scan: device upserts as they arrive, then a summary.
/// [done] throws a [ScanFailure] when the scan could not run.
class BridgeScan {
  const BridgeScan(this.devices, this.done);
  final Stream<DiscoveredDevice> devices;
  final Future<ScanSummary> done;
}

/// The LAN this device is on.
class LanInfo {
  const LanInfo({required this.ip, required this.cidr, this.gateway, this.dns, this.interfaceName, this.ssid});
  final String ip;
  final String cidr;
  final String? gateway;
  final String? dns;
  final String? interfaceName;

  /// Wi-Fi network name, when the OS reveals it.
  final String? ssid;

  /// Identifies the network in the local cache.
  String get key => '$cidr|${gateway ?? '-'}';

  /// Directed broadcast address, for Wake-on-LAN.
  String get broadcast {
    final [net, bits] = cidr.split('/');
    final prefix = int.parse(bits);
    final addr = net.split('.').fold<int>(0, (a, p) => (a << 8) | int.parse(p));
    final host = prefix >= 32 ? 0 : (1 << (32 - prefix)) - 1;
    final b = addr | host;
    return '${b >> 24 & 255}.${b >> 16 & 255}.${b >> 8 & 255}.${b & 255}';
  }
}

/// The app's view of the native engine, kept narrow so the scanner logic can
/// be tested with a fake.
abstract interface class ScannerBridge {
  /// The current LAN, or null when not connected to one.
  Future<LanInfo?> lanInfo();
  BridgeScan scan({String? cidr, Duration timeout});
  void cancel();

  /// Round-trip time in ms, or null when the host does not answer.
  Future<int?> ping(String ip, {Duration timeout});
  Future<Set<int>> openPorts(String ip, List<int> ports, {Duration timeout});
  Future<void> wakeOnLan(String mac, {String? broadcast});

  /// PingDuck agents announcing themselves over SSDP. Only UPnP discovery
  /// runs, so this is quick and is not a scan.
  Stream<DiscoveredDevice> findAgents({Duration timeout});
}

/// How a PingDuck agent describes itself over UPnP (agent/src/agent.hpp).
bool isPingDuckAgent(DiscoveredDevice d) => d.vendor == 'PingDuck' && d.services.contains('upnp:PingDuckAgent');

/// [ScannerBridge] backed by pingduck-core over FFI.
class FfiScannerBridge implements ScannerBridge {
  FfiScannerBridge({
    PingDuckCore? core,
    NetworkContextSource? network,
    AssetBundle? assets,
    this.ouiAsset = 'assets/oui_database/oui.csv',
  })  : _core = core ?? PingDuckCore.instance,
        _network = network ?? PlatformNetworkContextSource(),
        _assets = assets ?? rootBundle;

  final PingDuckCore _core;
  final NetworkContextSource _network;
  final AssetBundle _assets;
  final String ouiAsset;
  Future<void>? _ouiLoaded;

  @override
  Future<LanInfo?> lanInfo() async {
    final ctx = await _network.current();
    // Android hides the gateway from native code; hand it over before the
    // core picks its interface.
    _core.setLanHints(gateway: ctx?.gateway);
    final iface = _core.defaultInterface();
    final cidr = ctx?.cidr ?? iface?.cidr;
    final ip = ctx?.ip ?? iface?.ip;
    if (cidr == null || ip == null) return null;
    return LanInfo(
      ip: ip,
      cidr: cidr,
      gateway: ctx?.gateway ?? iface?.gateway,
      dns: iface?.dns,
      interfaceName: iface?.name,
      ssid: ctx?.ssid,
    );
  }

  @override
  BridgeScan scan({String? cidr, Duration timeout = const Duration(seconds: 3)}) {
    final devices = StreamController<DiscoveredDevice>();
    final done = _run(cidr, timeout, devices);
    return BridgeScan(devices.stream, done);
  }

  @override
  void cancel() => _core.cancel();

  @override
  Future<int?> ping(String ip, {Duration timeout = const Duration(seconds: 1)}) async =>
      (await _guard(() => _core.ping(ip, timeout: timeout)))?.inMilliseconds;

  @override
  Future<Set<int>> openPorts(String ip, List<int> ports, {Duration timeout = const Duration(milliseconds: 800)}) =>
      _guard(() => _core.openPorts(ip, ports, timeout: timeout));

  @override
  Future<void> wakeOnLan(String mac, {String? broadcast}) => _guard(() => _core.wakeOnLan(mac, broadcast: broadcast));

  @override
  Stream<DiscoveredDevice> findAgents({Duration timeout = const Duration(seconds: 4)}) async* {
    try {
      final session = _core.ssdp(timeout: timeout);
      await for (final d in session.devices) {
        final device = _toDevice(d);
        if (isPingDuckAgent(device)) yield device;
      }
      await session.done;
    } on PingDuckException catch (e) {
      throw ScanFailure(e.isPermission ? ScanFailureKind.permission : ScanFailureKind.other, e.message);
    }
  }

  Future<T> _guard<T>(Future<T> Function() op) async {
    try {
      return await op();
    } on PingDuckException catch (e) {
      throw ScanFailure(e.isPermission ? ScanFailureKind.permission : ScanFailureKind.other, e.message);
    }
  }

  Future<ScanSummary> _run(String? cidr, Duration timeout, StreamController<DiscoveredDevice> out) async {
    try {
      // Vendor names need the registry; load it once, off the UI isolate.
      await (_ouiLoaded ??= _loadOui());
      if (cidr == null && (await lanInfo()) == null) {
        throw const ScanFailure(ScanFailureKind.noNetwork, 'Not connected to a local network.');
      }
      final session = _core.scan(cidr: cidr, timeout: timeout);
      await for (final d in session.devices) {
        out.add(_toDevice(d));
      }
      final outcome = await session.done;
      return ScanSummary(deviceCount: outcome.deviceCount, cancelled: outcome.cancelled);
    } on PingDuckException catch (e) {
      throw ScanFailure(e.isPermission ? ScanFailureKind.permission : ScanFailureKind.other, e.message);
    } finally {
      await out.close();
    }
  }

  Future<void> _loadOui() async {
    try {
      final data = await _assets.load(ouiAsset);
      await _core.loadOui(data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes));
    } on FlutterError {
      // No bundled registry (e.g. a dev build without the asset): scans
      // still work, vendors just stay empty.
    }
  }

  static DiscoveredDevice _toDevice(PdDevice d) {
    final now = DateTime.now();
    return DiscoveredDevice(
      ip: d.ip,
      mac: d.mac,
      hostname: d.hostname,
      vendor: d.vendor,
      model: d.model,
      services: d.services,
      rttMs: d.rttMs,
      sources: DiscoverySource.fromMask(d.sources),
      isOnline: true,
      firstSeen: now,
      lastSeen: now,
    );
  }
}
