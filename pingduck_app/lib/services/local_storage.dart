import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import '../features/scanner/domain/discovered_device.dart';
import '../features/scanner/domain/remote_device.dart';

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

  /// Supabase `networks.id`, set when the person adds a monitoring unit on
  /// this network. Nothing about a network leaves the phone before that.
  TextColumn get remoteId => text().nullable()();
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

  /// Mirrors Supabase `devices.is_known` for agent-monitored networks.
  BoolColumn get isKnown => boolean().withDefault(const Constant(false))();

  /// Recognition signals: ping reply TTL and SSDP SERVER header.
  IntColumn get ttl => integer().nullable()();
  TextColumn get server => text().nullable()();

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
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) await _addColumn(m, networks, networks.ssid);
          if (from < 3) await _addColumn(m, networks, networks.remoteId);
          if (from < 4) await _addColumn(m, devices, devices.isKnown);
          if (from < 5) {
            await _addColumn(m, devices, devices.ttl);
            await _addColumn(m, devices, devices.server);
          }
        },
        beforeOpen: (_) async => customStatement('PRAGMA foreign_keys = ON'),
      );

  /// Adds [column] unless it is already there. An older build opening a
  /// newer database lowers the stored version but keeps the columns, so the
  /// next upgrade must not add them twice (a crash at launch).
  Future<void> _addColumn(Migrator m, TableInfo table, GeneratedColumn column) async {
    final existing = await customSelect('PRAGMA table_info("${table.actualTableName}")').get();
    if (existing.any((r) => r.read<String>('name') == column.name)) return;
    await m.addColumn(table, column);
  }

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

  Future<String?> remoteIdOf(int networkId) async =>
      (await (select(networks)..where((n) => n.id.equals(networkId))).getSingleOrNull())?.remoteId;

  /// Links a local network to its Supabase row; null forgets the link.
  Future<void> setRemoteId(int networkId, String? remoteId) =>
      (update(networks)..where((n) => n.id.equals(networkId))).write(NetworksCompanion(remoteId: Value(remoteId)));

  /// Local networks linked to a Supabase network, i.e. with a monitoring unit.
  Future<List<({int id, String remoteId})>> linkedNetworks() async {
    final rows = await (select(networks)..where((n) => n.remoteId.isNotNull())).get();
    return [for (final r in rows) (id: r.id, remoteId: r.remoteId!)];
  }

  /// Local networks not yet linked to a Supabase network.
  Future<List<({int id, String cidr, String? gateway, String? ssid})>> unlinkedNetworks() async {
    final rows = await (select(networks)..where((n) => n.remoteId.isNull())).get();
    return [for (final r in rows) (id: r.id, cidr: r.cidr, gateway: r.gateway, ssid: r.ssid)];
  }

  /// Folds the agent's view of a network into the cache, matching by IP (the
  /// only identity the phone and the agent both see). Fills MACs and missing
  /// names, never touches the user's names and notes, and adds devices only
  /// the agent sees. A MAC already cached under another IP is left for the
  /// next scan rather than duplicated. Returns the number of rows written.
  Future<int> mergeRemoteDevices(int networkId, List<RemoteDevice> remote) => transaction(() async {
        final local = await (select(devices)..where((d) => d.networkId.equals(networkId))).get();
        final byIp = {for (final d in local) d.ip: d};
        final macs = {for (final d in local) if (d.mac != null) d.mac!.toLowerCase(): d.ip};
        var written = 0;
        for (final r in remote) {
          final ip = r.ip;
          if (ip == null) continue;
          final mac = r.mac.toLowerCase();
          final row = byIp[ip];
          if (row != null) {
            final seen = r.lastSeenAt;
            await (update(devices)..where((d) => d.networkId.equals(networkId) & d.ip.equals(ip))).write(
              DevicesCompanion(
                mac: Value(mac),
                hostname: row.hostname == null ? Value(r.hostname) : const Value.absent(),
                vendor: row.vendor == null || (row.vendor!.startsWith('Private') && r.vendor != null)
                    ? Value(r.vendor)
                    : const Value.absent(),
                model: row.model == null ? Value(r.model) : const Value.absent(),
                services: row.services.isEmpty && r.services.isNotEmpty ? Value(r.services.join(',')) : const Value.absent(),
                ttl: row.ttl == null ? Value(r.ttl) : const Value.absent(),
                server: row.server == null ? Value(r.server) : const Value.absent(),
                sources: Value(row.sources | DiscoverySource.agent.bit),
                lastSeen: seen != null && (row.lastSeen == null || seen.isAfter(row.lastSeen!))
                    ? Value(seen)
                    : const Value.absent(),
                isKnown: Value(r.isKnown),
              ),
            );
            written++;
          } else if (!macs.containsKey(mac)) {
            await into(devices).insert(DevicesCompanion.insert(
              networkId: networkId,
              ip: ip,
              mac: Value(mac),
              hostname: Value(r.hostname),
              vendor: Value(r.vendor),
              model: Value(r.model),
              services: Value(r.services.join(',')),
              ttl: Value(r.ttl),
              server: Value(r.server),
              sources: Value(DiscoverySource.agent.bit),
              firstSeen: Value(r.firstSeenAt),
              lastSeen: Value(r.lastSeenAt),
              isKnown: Value(r.isKnown),
            ));
            macs[mac] = ip;
            written++;
          }
        }
        return written;
      });

  /// Sets the known flag of the cached device with [mac].
  Future<void> setKnown(int networkId, String mac, bool known) =>
      (update(devices)..where((d) => d.networkId.equals(networkId) & d.mac.lower().equals(mac.toLowerCase())))
          .write(DevicesCompanion(isKnown: Value(known)));

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
        isKnown: r.isKnown,
        ttl: r.ttl,
        server: r.server,
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
        isKnown: Value(d.isKnown),
        ttl: Value(d.ttl),
        server: Value(d.server),
      );
}
