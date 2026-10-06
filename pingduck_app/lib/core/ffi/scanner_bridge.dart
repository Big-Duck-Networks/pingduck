import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:pingduck_core/pingduck_core.dart';

import '../../features/scanner/domain/discovered_device.dart';
import '../network/network_context.dart';

/// Why a scan could not run.
enum ScanFailureKind { noNetwork, permission, other }

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

/// The app's view of the native engine, kept narrow so the scanner logic can
/// be tested with a fake.
abstract interface class ScannerBridge {
  BridgeScan scan({Duration timeout});
  void cancel();
}

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
  BridgeScan scan({Duration timeout = const Duration(seconds: 3)}) {
    final devices = StreamController<DiscoveredDevice>();
    final done = _run(timeout, devices);
    return BridgeScan(devices.stream, done);
  }

  @override
  void cancel() => _core.cancel();

  Future<ScanSummary> _run(Duration timeout, StreamController<DiscoveredDevice> out) async {
    try {
      // Vendor names need the registry; load it once, off the UI isolate.
      await (_ouiLoaded ??= _loadOui());

      final ctx = await _network.current();
      _core.setLanHints(gateway: ctx?.gateway);
      final cidr = ctx?.cidr;
      if (cidr == null && _core.defaultInterface() == null) {
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
