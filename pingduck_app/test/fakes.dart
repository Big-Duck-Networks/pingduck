import 'dart:async';

import 'package:drift/native.dart';
import 'package:pingduck_app/core/ffi/scanner_bridge.dart';
import 'package:pingduck_app/core/network/network_context.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/services/local_storage.dart';

const testLan =
    LanInfo(ip: '10.42.0.17', cidr: '10.42.0.0/24', gateway: '10.42.0.1', interfaceName: 'wlan0', ssid: 'CyberLab_5G');

LocalStore memoryStore() => LocalStore(NativeDatabase.memory());

/// Scripted bridge: the test pushes devices and then finishes the scan.
class FakeBridge implements ScannerBridge {
  StreamController<DiscoveredDevice>? devices;
  Completer<ScanSummary>? done;
  LanInfo? lan = testLan;
  int scans = 0, cancels = 0;
  String? lastCidr;
  List<int?> pingReplies = [];
  Set<int> open = {};
  List<int>? probedPorts;
  String? wokenMac;

  @override
  Future<LanInfo?> lanInfo() async => lan;

  @override
  BridgeScan scan({String? cidr, Duration timeout = const Duration(seconds: 3)}) {
    scans++;
    lastCidr = cidr;
    devices = StreamController();
    done = Completer();
    return BridgeScan(devices!.stream, done!.future);
  }

  @override
  void cancel() => cancels++;

  Future<void> finish({int count = 0, bool cancelled = false, ScanFailure? failure}) async {
    await devices!.close();
    failure == null
        ? done!.complete(ScanSummary(deviceCount: count, cancelled: cancelled))
        : done!.completeError(failure);
  }

  @override
  Future<int?> ping(String ip, {Duration timeout = const Duration(seconds: 1)}) async =>
      pingReplies.isEmpty ? null : pingReplies.removeAt(0);

  @override
  Future<Set<int>> openPorts(String ip, List<int> ports, {Duration timeout = const Duration(milliseconds: 800)}) async {
    probedPorts = ports;
    return open.intersection(ports.toSet());
  }

  @override
  Future<void> wakeOnLan(String mac, {String? broadcast}) async => wokenMac = mac;
}

class FakeLock implements MulticastLock {
  int held = 0;
  @override
  Future<void> acquire() async => held++;
  @override
  Future<void> release() async => held--;
}

DiscoveredDevice dev(String ip, {String? hostname, int? rtt, String? mac, String? vendor, List<String> services = const []}) =>
    DiscoveredDevice(
      ip: ip,
      hostname: hostname,
      rttMs: rtt,
      mac: mac,
      vendor: vendor,
      services: services,
      isOnline: true,
      sources: const {DiscoverySource.icmp},
      firstSeen: DateTime(2026, 10, 5),
      lastSeen: DateTime(2026, 10, 5),
    );
