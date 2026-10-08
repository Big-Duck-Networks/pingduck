import 'dart:async';

import 'package:drift/native.dart';
import 'package:pingduck_app/core/ffi/scanner_bridge.dart';
import 'package:pingduck_app/core/network/lan_connectivity.dart';
import 'package:pingduck_app/core/network/network_context.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/services/local_storage.dart';
import 'package:pingduck_app/services/scan_quota.dart';
import 'package:supabase_flutter/supabase_flutter.dart' show AuthException;

const testLan = LanInfo(
  ip: '10.42.0.17',
  cidr: '10.42.0.0/24',
  gateway: '10.42.0.1',
  interfaceName: 'wlan0',
  ssid: 'CyberLab_5G',
);

LocalStore memoryStore() => LocalStore(NativeDatabase.memory());

/// Plan check that allows every scan, or refuses once [allowed] or
/// [automaticAllowed] is false.
class FakeQuota implements ScanQuota {
  bool allowed = true, automaticAllowed = true;
  int claims = 0, automaticClaims = 0;

  @override
  Future<QuotaResult> claim() async {
    claims++;
    return QuotaResult(allowed: allowed, remaining: allowed ? null : 0);
  }

  @override
  Future<bool> claimAutomatic() async {
    automaticClaims++;
    return automaticAllowed;
  }
}

/// Email and password accounts held in [accounts] (email to password). Sign-ups
/// wait in [pending] until the test calls [clickLink]; every emailed reset
/// code is [goodCode].
class FakeAuth implements AccountAuth {
  FakeAuth({Map<String, String> accounts = const {}}) : accounts = {...accounts};
  final Map<String, String> accounts;
  static const goodCode = '123456';
  String? _email;
  final _changes = StreamController<String?>.broadcast();
  final resets = <String>[];
  final pending = <String>{};
  final _clicked = <String>{};

  void clickLink(String email) => _clicked.add(email);
  int deletions = 0;

  void _signedIn(String? email) => _changes.add(_email = email);

  static AuthException _err(String code) => AuthException(code, code: code);

  @override
  String? get email => _email;

  @override
  Stream<String?> emailChanges() async* {
    yield _email;
    yield* _changes.stream;
  }

  @override
  Future<void> signIn(String email, String password) async {
    if (accounts[email] != password) throw _err('invalid_credentials');
    _signedIn(email);
  }

  @override
  Future<bool> startSignUp(String email, String password) async {
    if (accounts.containsKey(email)) throw _err('email_exists');
    pending.add(email);
    return true;
  }

  @override
  Future<bool> completeSignUp(String email, String password) async {
    if (!pending.contains(email) || !_clicked.contains(email)) return false;
    pending.remove(email);
    accounts[email] = password;
    _signedIn(email);
    return true;
  }

  @override
  Future<void> sendPasswordReset(String email) async => resets.add(email);

  @override
  Future<void> finishPasswordReset(String email, String code, String newPassword) async {
    if (code != goodCode) throw _err('otp_expired');
    accounts[email] = newPassword;
    _signedIn(email);
  }

  @override
  Future<void> signOut() async => _signedIn(null);

  @override
  Future<void> deleteAccount() async {
    deletions++;
    accounts.remove(_email);
    _signedIn(null);
  }
}

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

/// Connectivity the test switches by hand.
class FakeLan implements LanConnectivity {
  FakeLan([this.connected = true]);
  bool connected;
  final _changes = StreamController<bool>.broadcast();

  void set(bool value) {
    connected = value;
    _changes.add(value);
  }

  @override
  Future<bool> current() async => connected;

  @override
  Stream<bool> changes() => _changes.stream;
}

class FakeLock implements MulticastLock {
  int held = 0;
  @override
  Future<void> acquire() async => held++;
  @override
  Future<void> release() async => held--;
}

DiscoveredDevice dev(
  String ip, {
  String? hostname,
  int? rtt,
  String? mac,
  String? vendor,
  List<String> services = const [],
}) => DiscoveredDevice(
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
