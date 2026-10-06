import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../features/scanner/domain/discovered_device.dart';

part 'local_storage.g.dart';

/// A LAN the app has scanned. Keyed by subnet + gateway: the gateway's MAC
/// (the roadmap's ideal key) is hidden from apps on Android.
class Networks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get key => text().unique()();
  TextColumn get cidr => text()();
  TextColumn get gateway => text().nullable()();
  DateTimeColumn get lastScanAt => dateTime().nullable()();

  /// Last Wi-Fi name seen on this network, so it shows before a scan.
  TextColumn get ssid => text().nullable()();
}

/// Devices per network, keyed by IP: without MACs (Android) the IP is the
/// only identity the app can observe. The agent adds MAC identity in Phase 4.
class Devices extends Table {
  IntColumn get networkId => integer().references(Networks, #id, onDelete: KeyAction.cascade)();
  TextColumn get ip => text()();
  TextColumn get mac => text().nullable()();
  TextColumn get hostname => text().nullable()();
  TextColumn get vendor => text().nullable()();
  TextColumn get model => text().nullable()();
  TextColumn get services => text().withDefault(const Constant(''))();
  IntColumn get sources => integer().withDefault(const Constant(0))();
  DateTimeColumn get firstSeen => dateTime().nullable()();
  DateTimeColumn get lastSeen => dateTime().nullable()();
  IntColumn get lastRttMs => integer().nullable()();
  TextColumn get rttHistory => text().withDefault(const Constant(''))();
  TextColumn get customName => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {networkId, ip};
}

/// A saved network as listed on the My Networks page.
class NetworkSummary {
  const NetworkSummary({
    required this.id,
    required this.cidr,
    this.gateway,
    this.ssid,
    this.lastScanAt,
    required this.deviceCount,
  });

  final int id;
  final String cidr;
  final String? gateway;
  final String? ssid;
  final DateTime? lastScanAt;
  final int deviceCount;

  /// Wi-Fi name when known, else the subnet.
  String get name => ssid ?? cidr;
}

class Settings extends Table {
  TextColumn get key => text()();
  TextColumn get value => text()();

  @override
  Set<Column> get primaryKey => {key};
}

@DriftDatabase(tables: [Networks, Devices, Settings])
class LocalStore extends _$LocalStore {
  LocalStore([QueryExecutor? executor]) : super(executor ?? driftDatabase(name: 'pingduck'));

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await m.addColumn(networks, networks.ssid);
        },
        beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
      );

  /// Returns the id of the network with [key], creating it if needed.
  Future<int> networkFor({required String key, required String cidr, String? gateway}) async {
    final existing = await (select(networks)..where((n) => n.key.equals(key))).getSingleOrNull();
    if (existing != null) return existing.id;
    return into(networks).insert(NetworksCompanion.insert(key: key, cidr: cidr, gateway: Value(gateway)));
  }

  /// Records a finished scan; a null [ssid] keeps the last known name.
  Future<void> markScanned(int networkId, DateTime at, {String? ssid}) =>
      (update(networks)..where((n) => n.id.equals(networkId))).write(NetworksCompanion(
        lastScanAt: Value(at),
        ssid: ssid == null ? const Value.absent() : Value(ssid),
      ));

  Future<String?> ssidOf(int networkId) async =>
      (await (select(networks)..where((n) => n.id.equals(networkId))).getSingleOrNull())?.ssid;

  /// Every cached device of a network, all marked offline until they answer.
  Future<List<DiscoveredDevice>> devicesOf(int networkId) async {
    final rows = await (select(devices)..where((d) => d.networkId.equals(networkId))).get();
    return [for (final r in rows) _fromRow(r)];
  }

  Future<void> saveDevices(int networkId, Iterable<DiscoveredDevice> list) => batch((b) {
        b.insertAllOnConflictUpdate(devices, [for (final d in list) _toRow(networkId, d)]);
      });

  /// How much the app keeps on this device.
  Future<({int networks, int devices})> usage() async {
    final n = await (selectOnly(networks)..addColumns([networks.id.count()])).getSingle();
    final d = await (selectOnly(devices)..addColumns([devices.ip.count()])).getSingle();
    return (networks: n.read(networks.id.count()) ?? 0, devices: d.read(devices.ip.count()) ?? 0);
  }

  /// Deletes every network and device (and their notes and names). Settings
  /// such as onboarding and the permission prompt are kept.
  Future<void> clearInventory() => transaction(() async {
        await delete(devices).go();
        await delete(networks).go();
        await (delete(settings)..where((s) => s.key.equals('lastNetworkId'))).go();
      });

  /// Every saved network with its device count, most recently scanned first.
  Future<List<NetworkSummary>> networkSummaries() async {
    final count = devices.ip.count();
    final rows = await (select(networks).join([leftOuterJoin(devices, devices.networkId.equalsExp(networks.id))])
          ..groupBy([networks.id])
          ..addColumns([count]))
        .get();
    final list = [
      for (final r in rows)
        NetworkSummary(
          id: r.readTable(networks).id,
          cidr: r.readTable(networks).cidr,
          gateway: r.readTable(networks).gateway,
          ssid: r.readTable(networks).ssid,
          lastScanAt: r.readTable(networks).lastScanAt,
          deviceCount: r.read(count) ?? 0,
        ),
    ];
    // Scan times are stored to the second; newer networks win ties.
    list.sort((a, b) {
      final t = (b.lastScanAt ?? DateTime(0)).compareTo(a.lastScanAt ?? DateTime(0));
      return t != 0 ? t : b.id.compareTo(a.id);
    });
    return list;
  }

  /// Deletes a network and (by cascade) its devices, names and notes.
  Future<void> forgetNetwork(int networkId) => transaction(() async {
        await (delete(devices)..where((d) => d.networkId.equals(networkId))).go();
        await (delete(networks)..where((n) => n.id.equals(networkId))).go();
        if (await setting('lastNetworkId') == '$networkId') {
          await (delete(settings)..where((s) => s.key.equals('lastNetworkId'))).go();
        }
      });

  Future<void> forgetDevice(int networkId, String ip) =>
      (delete(devices)..where((d) => d.networkId.equals(networkId) & d.ip.equals(ip))).go();

  Future<String?> setting(String key) async =>
      (await (select(settings)..where((s) => s.key.equals(key))).getSingleOrNull())?.value;

  Future<void> setSetting(String key, String value) =>
      into(settings).insertOnConflictUpdate(SettingsCompanion.insert(key: key, value: value));

  static DiscoveredDevice _fromRow(Device r) => DiscoveredDevice(
        ip: r.ip,
        mac: r.mac,
        hostname: r.hostname,
        vendor: r.vendor,
        model: r.model,
        services: r.services.isEmpty ? const [] : r.services.split(','),
        sources: DiscoverySource.fromMask(r.sources),
        firstSeen: r.firstSeen,
        lastSeen: r.lastSeen,
        customName: r.customName,
        notes: r.notes,
        rttHistory: r.rttHistory.isEmpty ? const [] : [for (final s in r.rttHistory.split(',')) int.tryParse(s) ?? 0],
      );

  static DevicesCompanion _toRow(int networkId, DiscoveredDevice d) => DevicesCompanion.insert(
        networkId: networkId,
        ip: d.ip,
        mac: Value(d.mac),
        hostname: Value(d.hostname),
        vendor: Value(d.vendor),
        model: Value(d.model),
        services: Value(d.services.join(',')),
        sources: Value(DiscoverySource.toMask(d.sources)),
        firstSeen: Value(d.firstSeen),
        lastSeen: Value(d.lastSeen),
        lastRttMs: Value(d.rttMs),
        rttHistory: Value(d.rttHistory.join(',')),
        customName: Value(d.customName),
        notes: Value(d.notes),
      );
}
