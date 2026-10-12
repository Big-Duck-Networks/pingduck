import 'dart:async';

import 'package:drift/native.dart';
import 'package:pingduck_app/core/ffi/scanner_bridge.dart';
import 'package:pingduck_app/core/network/lan_connectivity.dart';
import 'package:pingduck_app/core/network/network_context.dart';
import 'package:pingduck_app/features/agent/data/agent_lan_client.dart';
import 'package:pingduck_app/features/agent/data/agent_repository.dart';
import 'package:pingduck_app/features/agent/domain/agent_platform.dart';
import 'package:pingduck_app/features/agent/domain/agent_unit.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/features/scanner/domain/remote_device.dart';
import 'package:pingduck_app/services/local_storage.dart';
import 'package:pingduck_app/services/push_alerts.dart';
import 'package:pingduck_app/services/scan_quota.dart';
import 'package:pingduck_app/services/supabase_sync.dart';
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

  /// What [findAgents] reports; each search counts in [agentSearches].
  List<DiscoveredDevice> agents = [];
  int agentSearches = 0;

  @override
  Stream<DiscoveredDevice> findAgents({Duration timeout = const Duration(seconds: 4)}) {
    agentSearches++;
    return Stream.fromIterable(agents);
  }
}

/// Agents on the fake LAN, by IP. [pair] redeems against [repo] like the
/// real agent does with Supabase.
class FakeAgentLan implements AgentLanClient {
  FakeAgentLan(this.repo);
  final FakeAgentRepository repo;
  final agents = <String, FoundAgent>{};
  final pairCalls = <(String, String)>[];
  PairOutcome? forceOutcome;

  @override
  Future<FoundAgent?> info(String ip) async => agents[ip];

  @override
  Future<PairResult> pair(String ip, String code) async {
    pairCalls.add((ip, code));
    final a = agents[ip];
    if (a == null) return (outcome: PairOutcome.unreachable, agentId: null);
    if (forceOutcome != null) return (outcome: forceOutcome!, agentId: null);
    if (a.paired) return (outcome: PairOutcome.alreadyPaired, agentId: null);
    final paired = repo.redeem(code, a.name);
    if (paired == null) return (outcome: PairOutcome.invalidCode, agentId: null);
    agents[ip] = FoundAgent(ip: ip, instanceId: a.instanceId, name: a.name, version: a.version, paired: true, agentId: paired.id);
    return (outcome: PairOutcome.paired, agentId: paired.id);
  }
}

FoundAgent agentAt(String ip, {String name = 'homelab', bool paired = false, String? agentId}) =>
    FoundAgent(ip: ip, instanceId: 'inst-$ip', name: name, version: '0.9.0', paired: paired, agentId: agentId);

/// The server side of pairing, in memory.
class FakeAgentRepository implements AgentRepository {
  int slots = 2;
  bool offline = false;
  final agents = <PairedAgent>[];
  final networks = <int, String>{};
  final codes = <String, String>{}; // code -> network id
  final emails = <AgentPlatform>[];
  final revoked = <String>[];
  int registrations = 0;
  int _next = 0;

  /// What the agent's claim_pairing_code does.
  PairedAgent? redeem(String code, String name) {
    final network = codes.remove(code);
    if (network == null) return null;
    final a = PairedAgent(id: 'agent-${++_next}', networkId: network, name: name, version: '0.9.0', lastSeenAt: DateTime.now(), createdAt: DateTime.now());
    agents.insert(0, a);
    return a;
  }

  void _check() {
    if (offline) throw Exception('offline');
  }

  @override
  Future<int> maxMonitoredNetworks() async {
    _check();
    return slots;
  }

  @override
  Future<String> ensureRemoteNetwork(int localNetworkId, LanInfo lan) async {
    _check();
    registrations++;
    return networks.putIfAbsent(localNetworkId, () => 'net-$localNetworkId');
  }

  @override
  Future<PairingCode> createCode(String networkId) async {
    _check();
    if (slots == 0) throw const PlanLimitException();
    final code = 'ABCD234${codes.length + 2}';
    codes[code] = networkId;
    return (code: code, expiresAt: DateTime.now().add(const Duration(minutes: 10)));
  }

  @override
  Future<List<PairedAgent>> myAgents() async {
    _check();
    return List.of(agents);
  }

  @override
  Future<void> revoke(String agentId) async {
    _check();
    revoked.add(agentId);
    agents.removeWhere((a) => a.id == agentId);
  }

  @override
  Future<String> emailInstructions(AgentPlatform platform) async {
    _check();
    emails.add(platform);
    return 'me@example.com';
  }
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

/// Supabase `devices` per remote network id, with a change stream the test
/// drives through [change].
class FakeSyncRepository implements SyncRepository {
  final rows = <String, List<RemoteDevice>>{};
  final fetches = <String>[];
  final known = <(String, String), bool>{};
  final _changes = <String, StreamController<void>>{};

  /// Networks with an open change subscription.
  Iterable<String> get listening => _changes.entries.where((e) => e.value.hasListener).map((e) => e.key);

  void change(String remoteId) => _changes[remoteId]?.add(null);

  @override
  Future<List<RemoteDevice>> devicesOf(String remoteNetworkId) async {
    fetches.add(remoteNetworkId);
    return rows[remoteNetworkId] ?? const [];
  }

  @override
  Stream<void> changesOf(String remoteNetworkId) =>
      (_changes[remoteNetworkId] = StreamController<void>.broadcast()).stream;

  @override
  Future<void> setKnown(String remoteNetworkId, String mac, bool value) async =>
      known[(remoteNetworkId, mac)] = value;

  @override
  Future<void> markAllKnown(String remoteNetworkId) async {
    for (final d in rows[remoteNetworkId] ?? const <RemoteDevice>[]) {
      known[(remoteNetworkId, d.mac)] = true;
    }
  }
}

class FakePushAlerts implements PushAlerts {
  bool enabled = false;
  bool deny = false;
  final calls = <String>[];

  @override
  Future<bool> isEnabled() async => enabled;

  @override
  Future<void> enable() async {
    calls.add('enable');
    if (deny) throw const NotificationsDeniedException();
    enabled = true;
  }

  @override
  Future<void> disable() async {
    calls.add('disable');
    enabled = false;
  }

  @override
  void listen(Future<void> Function() onAlert) => calls.add('listen');
}
