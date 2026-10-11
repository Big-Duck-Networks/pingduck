// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'local_storage.dart';

// ignore_for_file: type=lint
class $NetworksTable extends Networks with TableInfo<$NetworksTable, Network> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $NetworksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<int> id = GeneratedColumn<int>(
    'id',
    aliasedName,
    false,
    hasAutoIncrement: true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'PRIMARY KEY AUTOINCREMENT',
    ),
  );
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways('UNIQUE'),
  );
  static const VerificationMeta _cidrMeta = const VerificationMeta('cidr');
  @override
  late final GeneratedColumn<String> cidr = GeneratedColumn<String>(
    'cidr',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _gatewayMeta = const VerificationMeta(
    'gateway',
  );
  @override
  late final GeneratedColumn<String> gateway = GeneratedColumn<String>(
    'gateway',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastScanAtMeta = const VerificationMeta(
    'lastScanAt',
  );
  @override
  late final GeneratedColumn<DateTime> lastScanAt = GeneratedColumn<DateTime>(
    'last_scan_at',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _ssidMeta = const VerificationMeta('ssid');
  @override
  late final GeneratedColumn<String> ssid = GeneratedColumn<String>(
    'ssid',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _remoteIdMeta = const VerificationMeta(
    'remoteId',
  );
  @override
  late final GeneratedColumn<String> remoteId = GeneratedColumn<String>(
    'remote_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    key,
    cidr,
    gateway,
    lastScanAt,
    ssid,
    remoteId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'networks';
  @override
  VerificationContext validateIntegrity(
    Insertable<Network> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    }
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('cidr')) {
      context.handle(
        _cidrMeta,
        cidr.isAcceptableOrUnknown(data['cidr']!, _cidrMeta),
      );
    } else if (isInserting) {
      context.missing(_cidrMeta);
    }
    if (data.containsKey('gateway')) {
      context.handle(
        _gatewayMeta,
        gateway.isAcceptableOrUnknown(data['gateway']!, _gatewayMeta),
      );
    }
    if (data.containsKey('last_scan_at')) {
      context.handle(
        _lastScanAtMeta,
        lastScanAt.isAcceptableOrUnknown(
          data['last_scan_at']!,
          _lastScanAtMeta,
        ),
      );
    }
    if (data.containsKey('ssid')) {
      context.handle(
        _ssidMeta,
        ssid.isAcceptableOrUnknown(data['ssid']!, _ssidMeta),
      );
    }
    if (data.containsKey('remote_id')) {
      context.handle(
        _remoteIdMeta,
        remoteId.isAcceptableOrUnknown(data['remote_id']!, _remoteIdMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  Network map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Network(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}id'],
      )!,
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      cidr: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}cidr'],
      )!,
      gateway: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}gateway'],
      ),
      lastScanAt: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_scan_at'],
      ),
      ssid: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ssid'],
      ),
      remoteId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}remote_id'],
      ),
    );
  }

  @override
  $NetworksTable createAlias(String alias) {
    return $NetworksTable(attachedDatabase, alias);
  }
}

class Network extends DataClass implements Insertable<Network> {
  final int id;
  final String key;
  final String cidr;
  final String? gateway;
  final DateTime? lastScanAt;

  /// Last Wi-Fi name seen on this network, so it shows before a scan.
  final String? ssid;

  /// Supabase `networks.id`, set when the person adds a monitoring unit on
  /// this network. Nothing about a network leaves the phone before that.
  final String? remoteId;
  const Network({
    required this.id,
    required this.key,
    required this.cidr,
    this.gateway,
    this.lastScanAt,
    this.ssid,
    this.remoteId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<int>(id);
    map['key'] = Variable<String>(key);
    map['cidr'] = Variable<String>(cidr);
    if (!nullToAbsent || gateway != null) {
      map['gateway'] = Variable<String>(gateway);
    }
    if (!nullToAbsent || lastScanAt != null) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt);
    }
    if (!nullToAbsent || ssid != null) {
      map['ssid'] = Variable<String>(ssid);
    }
    if (!nullToAbsent || remoteId != null) {
      map['remote_id'] = Variable<String>(remoteId);
    }
    return map;
  }

  NetworksCompanion toCompanion(bool nullToAbsent) {
    return NetworksCompanion(
      id: Value(id),
      key: Value(key),
      cidr: Value(cidr),
      gateway: gateway == null && nullToAbsent
          ? const Value.absent()
          : Value(gateway),
      lastScanAt: lastScanAt == null && nullToAbsent
          ? const Value.absent()
          : Value(lastScanAt),
      ssid: ssid == null && nullToAbsent ? const Value.absent() : Value(ssid),
      remoteId: remoteId == null && nullToAbsent
          ? const Value.absent()
          : Value(remoteId),
    );
  }

  factory Network.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Network(
      id: serializer.fromJson<int>(json['id']),
      key: serializer.fromJson<String>(json['key']),
      cidr: serializer.fromJson<String>(json['cidr']),
      gateway: serializer.fromJson<String?>(json['gateway']),
      lastScanAt: serializer.fromJson<DateTime?>(json['lastScanAt']),
      ssid: serializer.fromJson<String?>(json['ssid']),
      remoteId: serializer.fromJson<String?>(json['remoteId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<int>(id),
      'key': serializer.toJson<String>(key),
      'cidr': serializer.toJson<String>(cidr),
      'gateway': serializer.toJson<String?>(gateway),
      'lastScanAt': serializer.toJson<DateTime?>(lastScanAt),
      'ssid': serializer.toJson<String?>(ssid),
      'remoteId': serializer.toJson<String?>(remoteId),
    };
  }

  Network copyWith({
    int? id,
    String? key,
    String? cidr,
    Value<String?> gateway = const Value.absent(),
    Value<DateTime?> lastScanAt = const Value.absent(),
    Value<String?> ssid = const Value.absent(),
    Value<String?> remoteId = const Value.absent(),
  }) => Network(
    id: id ?? this.id,
    key: key ?? this.key,
    cidr: cidr ?? this.cidr,
    gateway: gateway.present ? gateway.value : this.gateway,
    lastScanAt: lastScanAt.present ? lastScanAt.value : this.lastScanAt,
    ssid: ssid.present ? ssid.value : this.ssid,
    remoteId: remoteId.present ? remoteId.value : this.remoteId,
  );
  Network copyWithCompanion(NetworksCompanion data) {
    return Network(
      id: data.id.present ? data.id.value : this.id,
      key: data.key.present ? data.key.value : this.key,
      cidr: data.cidr.present ? data.cidr.value : this.cidr,
      gateway: data.gateway.present ? data.gateway.value : this.gateway,
      lastScanAt: data.lastScanAt.present
          ? data.lastScanAt.value
          : this.lastScanAt,
      ssid: data.ssid.present ? data.ssid.value : this.ssid,
      remoteId: data.remoteId.present ? data.remoteId.value : this.remoteId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Network(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('cidr: $cidr, ')
          ..write('gateway: $gateway, ')
          ..write('lastScanAt: $lastScanAt, ')
          ..write('ssid: $ssid, ')
          ..write('remoteId: $remoteId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, key, cidr, gateway, lastScanAt, ssid, remoteId);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Network &&
          other.id == this.id &&
          other.key == this.key &&
          other.cidr == this.cidr &&
          other.gateway == this.gateway &&
          other.lastScanAt == this.lastScanAt &&
          other.ssid == this.ssid &&
          other.remoteId == this.remoteId);
}

class NetworksCompanion extends UpdateCompanion<Network> {
  final Value<int> id;
  final Value<String> key;
  final Value<String> cidr;
  final Value<String?> gateway;
  final Value<DateTime?> lastScanAt;
  final Value<String?> ssid;
  final Value<String?> remoteId;
  const NetworksCompanion({
    this.id = const Value.absent(),
    this.key = const Value.absent(),
    this.cidr = const Value.absent(),
    this.gateway = const Value.absent(),
    this.lastScanAt = const Value.absent(),
    this.ssid = const Value.absent(),
    this.remoteId = const Value.absent(),
  });
  NetworksCompanion.insert({
    this.id = const Value.absent(),
    required String key,
    required String cidr,
    this.gateway = const Value.absent(),
    this.lastScanAt = const Value.absent(),
    this.ssid = const Value.absent(),
    this.remoteId = const Value.absent(),
  }) : key = Value(key),
       cidr = Value(cidr);
  static Insertable<Network> custom({
    Expression<int>? id,
    Expression<String>? key,
    Expression<String>? cidr,
    Expression<String>? gateway,
    Expression<DateTime>? lastScanAt,
    Expression<String>? ssid,
    Expression<String>? remoteId,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (key != null) 'key': key,
      if (cidr != null) 'cidr': cidr,
      if (gateway != null) 'gateway': gateway,
      if (lastScanAt != null) 'last_scan_at': lastScanAt,
      if (ssid != null) 'ssid': ssid,
      if (remoteId != null) 'remote_id': remoteId,
    });
  }

  NetworksCompanion copyWith({
    Value<int>? id,
    Value<String>? key,
    Value<String>? cidr,
    Value<String?>? gateway,
    Value<DateTime?>? lastScanAt,
    Value<String?>? ssid,
    Value<String?>? remoteId,
  }) {
    return NetworksCompanion(
      id: id ?? this.id,
      key: key ?? this.key,
      cidr: cidr ?? this.cidr,
      gateway: gateway ?? this.gateway,
      lastScanAt: lastScanAt ?? this.lastScanAt,
      ssid: ssid ?? this.ssid,
      remoteId: remoteId ?? this.remoteId,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<int>(id.value);
    }
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (cidr.present) {
      map['cidr'] = Variable<String>(cidr.value);
    }
    if (gateway.present) {
      map['gateway'] = Variable<String>(gateway.value);
    }
    if (lastScanAt.present) {
      map['last_scan_at'] = Variable<DateTime>(lastScanAt.value);
    }
    if (ssid.present) {
      map['ssid'] = Variable<String>(ssid.value);
    }
    if (remoteId.present) {
      map['remote_id'] = Variable<String>(remoteId.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('NetworksCompanion(')
          ..write('id: $id, ')
          ..write('key: $key, ')
          ..write('cidr: $cidr, ')
          ..write('gateway: $gateway, ')
          ..write('lastScanAt: $lastScanAt, ')
          ..write('ssid: $ssid, ')
          ..write('remoteId: $remoteId')
          ..write(')'))
        .toString();
  }
}

class $DevicesTable extends Devices with TableInfo<$DevicesTable, Device> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DevicesTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _networkIdMeta = const VerificationMeta(
    'networkId',
  );
  @override
  late final GeneratedColumn<int> networkId = GeneratedColumn<int>(
    'network_id',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES networks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _ipMeta = const VerificationMeta('ip');
  @override
  late final GeneratedColumn<String> ip = GeneratedColumn<String>(
    'ip',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _macMeta = const VerificationMeta('mac');
  @override
  late final GeneratedColumn<String> mac = GeneratedColumn<String>(
    'mac',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _hostnameMeta = const VerificationMeta(
    'hostname',
  );
  @override
  late final GeneratedColumn<String> hostname = GeneratedColumn<String>(
    'hostname',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _vendorMeta = const VerificationMeta('vendor');
  @override
  late final GeneratedColumn<String> vendor = GeneratedColumn<String>(
    'vendor',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _servicesMeta = const VerificationMeta(
    'services',
  );
  @override
  late final GeneratedColumn<String> services = GeneratedColumn<String>(
    'services',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _sourcesMeta = const VerificationMeta(
    'sources',
  );
  @override
  late final GeneratedColumn<int> sources = GeneratedColumn<int>(
    'sources',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _firstSeenMeta = const VerificationMeta(
    'firstSeen',
  );
  @override
  late final GeneratedColumn<DateTime> firstSeen = GeneratedColumn<DateTime>(
    'first_seen',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSeenMeta = const VerificationMeta(
    'lastSeen',
  );
  @override
  late final GeneratedColumn<DateTime> lastSeen = GeneratedColumn<DateTime>(
    'last_seen',
    aliasedName,
    true,
    type: DriftSqlType.dateTime,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastRttMsMeta = const VerificationMeta(
    'lastRttMs',
  );
  @override
  late final GeneratedColumn<int> lastRttMs = GeneratedColumn<int>(
    'last_rtt_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _rttHistoryMeta = const VerificationMeta(
    'rttHistory',
  );
  @override
  late final GeneratedColumn<String> rttHistory = GeneratedColumn<String>(
    'rtt_history',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant(''),
  );
  static const VerificationMeta _customNameMeta = const VerificationMeta(
    'customName',
  );
  @override
  late final GeneratedColumn<String> customName = GeneratedColumn<String>(
    'custom_name',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _notesMeta = const VerificationMeta('notes');
  @override
  late final GeneratedColumn<String> notes = GeneratedColumn<String>(
    'notes',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    networkId,
    ip,
    mac,
    hostname,
    vendor,
    model,
    services,
    sources,
    firstSeen,
    lastSeen,
    lastRttMs,
    rttHistory,
    customName,
    notes,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'devices';
  @override
  VerificationContext validateIntegrity(
    Insertable<Device> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('network_id')) {
      context.handle(
        _networkIdMeta,
        networkId.isAcceptableOrUnknown(data['network_id']!, _networkIdMeta),
      );
    } else if (isInserting) {
      context.missing(_networkIdMeta);
    }
    if (data.containsKey('ip')) {
      context.handle(_ipMeta, ip.isAcceptableOrUnknown(data['ip']!, _ipMeta));
    } else if (isInserting) {
      context.missing(_ipMeta);
    }
    if (data.containsKey('mac')) {
      context.handle(
        _macMeta,
        mac.isAcceptableOrUnknown(data['mac']!, _macMeta),
      );
    }
    if (data.containsKey('hostname')) {
      context.handle(
        _hostnameMeta,
        hostname.isAcceptableOrUnknown(data['hostname']!, _hostnameMeta),
      );
    }
    if (data.containsKey('vendor')) {
      context.handle(
        _vendorMeta,
        vendor.isAcceptableOrUnknown(data['vendor']!, _vendorMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('services')) {
      context.handle(
        _servicesMeta,
        services.isAcceptableOrUnknown(data['services']!, _servicesMeta),
      );
    }
    if (data.containsKey('sources')) {
      context.handle(
        _sourcesMeta,
        sources.isAcceptableOrUnknown(data['sources']!, _sourcesMeta),
      );
    }
    if (data.containsKey('first_seen')) {
      context.handle(
        _firstSeenMeta,
        firstSeen.isAcceptableOrUnknown(data['first_seen']!, _firstSeenMeta),
      );
    }
    if (data.containsKey('last_seen')) {
      context.handle(
        _lastSeenMeta,
        lastSeen.isAcceptableOrUnknown(data['last_seen']!, _lastSeenMeta),
      );
    }
    if (data.containsKey('last_rtt_ms')) {
      context.handle(
        _lastRttMsMeta,
        lastRttMs.isAcceptableOrUnknown(data['last_rtt_ms']!, _lastRttMsMeta),
      );
    }
    if (data.containsKey('rtt_history')) {
      context.handle(
        _rttHistoryMeta,
        rttHistory.isAcceptableOrUnknown(data['rtt_history']!, _rttHistoryMeta),
      );
    }
    if (data.containsKey('custom_name')) {
      context.handle(
        _customNameMeta,
        customName.isAcceptableOrUnknown(data['custom_name']!, _customNameMeta),
      );
    }
    if (data.containsKey('notes')) {
      context.handle(
        _notesMeta,
        notes.isAcceptableOrUnknown(data['notes']!, _notesMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {networkId, ip};
  @override
  Device map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Device(
      networkId: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}network_id'],
      )!,
      ip: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}ip'],
      )!,
      mac: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mac'],
      ),
      hostname: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hostname'],
      ),
      vendor: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}vendor'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      services: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}services'],
      )!,
      sources: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}sources'],
      )!,
      firstSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}first_seen'],
      ),
      lastSeen: attachedDatabase.typeMapping.read(
        DriftSqlType.dateTime,
        data['${effectivePrefix}last_seen'],
      ),
      lastRttMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}last_rtt_ms'],
      ),
      rttHistory: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}rtt_history'],
      )!,
      customName: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}custom_name'],
      ),
      notes: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}notes'],
      ),
    );
  }

  @override
  $DevicesTable createAlias(String alias) {
    return $DevicesTable(attachedDatabase, alias);
  }
}

class Device extends DataClass implements Insertable<Device> {
  final int networkId;
  final String ip;
  final String? mac;
  final String? hostname;
  final String? vendor;
  final String? model;
  final String services;
  final int sources;
  final DateTime? firstSeen;
  final DateTime? lastSeen;
  final int? lastRttMs;
  final String rttHistory;
  final String? customName;
  final String? notes;
  const Device({
    required this.networkId,
    required this.ip,
    this.mac,
    this.hostname,
    this.vendor,
    this.model,
    required this.services,
    required this.sources,
    this.firstSeen,
    this.lastSeen,
    this.lastRttMs,
    required this.rttHistory,
    this.customName,
    this.notes,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['network_id'] = Variable<int>(networkId);
    map['ip'] = Variable<String>(ip);
    if (!nullToAbsent || mac != null) {
      map['mac'] = Variable<String>(mac);
    }
    if (!nullToAbsent || hostname != null) {
      map['hostname'] = Variable<String>(hostname);
    }
    if (!nullToAbsent || vendor != null) {
      map['vendor'] = Variable<String>(vendor);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    map['services'] = Variable<String>(services);
    map['sources'] = Variable<int>(sources);
    if (!nullToAbsent || firstSeen != null) {
      map['first_seen'] = Variable<DateTime>(firstSeen);
    }
    if (!nullToAbsent || lastSeen != null) {
      map['last_seen'] = Variable<DateTime>(lastSeen);
    }
    if (!nullToAbsent || lastRttMs != null) {
      map['last_rtt_ms'] = Variable<int>(lastRttMs);
    }
    map['rtt_history'] = Variable<String>(rttHistory);
    if (!nullToAbsent || customName != null) {
      map['custom_name'] = Variable<String>(customName);
    }
    if (!nullToAbsent || notes != null) {
      map['notes'] = Variable<String>(notes);
    }
    return map;
  }

  DevicesCompanion toCompanion(bool nullToAbsent) {
    return DevicesCompanion(
      networkId: Value(networkId),
      ip: Value(ip),
      mac: mac == null && nullToAbsent ? const Value.absent() : Value(mac),
      hostname: hostname == null && nullToAbsent
          ? const Value.absent()
          : Value(hostname),
      vendor: vendor == null && nullToAbsent
          ? const Value.absent()
          : Value(vendor),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      services: Value(services),
      sources: Value(sources),
      firstSeen: firstSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(firstSeen),
      lastSeen: lastSeen == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSeen),
      lastRttMs: lastRttMs == null && nullToAbsent
          ? const Value.absent()
          : Value(lastRttMs),
      rttHistory: Value(rttHistory),
      customName: customName == null && nullToAbsent
          ? const Value.absent()
          : Value(customName),
      notes: notes == null && nullToAbsent
          ? const Value.absent()
          : Value(notes),
    );
  }

  factory Device.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Device(
      networkId: serializer.fromJson<int>(json['networkId']),
      ip: serializer.fromJson<String>(json['ip']),
      mac: serializer.fromJson<String?>(json['mac']),
      hostname: serializer.fromJson<String?>(json['hostname']),
      vendor: serializer.fromJson<String?>(json['vendor']),
      model: serializer.fromJson<String?>(json['model']),
      services: serializer.fromJson<String>(json['services']),
      sources: serializer.fromJson<int>(json['sources']),
      firstSeen: serializer.fromJson<DateTime?>(json['firstSeen']),
      lastSeen: serializer.fromJson<DateTime?>(json['lastSeen']),
      lastRttMs: serializer.fromJson<int?>(json['lastRttMs']),
      rttHistory: serializer.fromJson<String>(json['rttHistory']),
      customName: serializer.fromJson<String?>(json['customName']),
      notes: serializer.fromJson<String?>(json['notes']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'networkId': serializer.toJson<int>(networkId),
      'ip': serializer.toJson<String>(ip),
      'mac': serializer.toJson<String?>(mac),
      'hostname': serializer.toJson<String?>(hostname),
      'vendor': serializer.toJson<String?>(vendor),
      'model': serializer.toJson<String?>(model),
      'services': serializer.toJson<String>(services),
      'sources': serializer.toJson<int>(sources),
      'firstSeen': serializer.toJson<DateTime?>(firstSeen),
      'lastSeen': serializer.toJson<DateTime?>(lastSeen),
      'lastRttMs': serializer.toJson<int?>(lastRttMs),
      'rttHistory': serializer.toJson<String>(rttHistory),
      'customName': serializer.toJson<String?>(customName),
      'notes': serializer.toJson<String?>(notes),
    };
  }

  Device copyWith({
    int? networkId,
    String? ip,
    Value<String?> mac = const Value.absent(),
    Value<String?> hostname = const Value.absent(),
    Value<String?> vendor = const Value.absent(),
    Value<String?> model = const Value.absent(),
    String? services,
    int? sources,
    Value<DateTime?> firstSeen = const Value.absent(),
    Value<DateTime?> lastSeen = const Value.absent(),
    Value<int?> lastRttMs = const Value.absent(),
    String? rttHistory,
    Value<String?> customName = const Value.absent(),
    Value<String?> notes = const Value.absent(),
  }) => Device(
    networkId: networkId ?? this.networkId,
    ip: ip ?? this.ip,
    mac: mac.present ? mac.value : this.mac,
    hostname: hostname.present ? hostname.value : this.hostname,
    vendor: vendor.present ? vendor.value : this.vendor,
    model: model.present ? model.value : this.model,
    services: services ?? this.services,
    sources: sources ?? this.sources,
    firstSeen: firstSeen.present ? firstSeen.value : this.firstSeen,
    lastSeen: lastSeen.present ? lastSeen.value : this.lastSeen,
    lastRttMs: lastRttMs.present ? lastRttMs.value : this.lastRttMs,
    rttHistory: rttHistory ?? this.rttHistory,
    customName: customName.present ? customName.value : this.customName,
    notes: notes.present ? notes.value : this.notes,
  );
  Device copyWithCompanion(DevicesCompanion data) {
    return Device(
      networkId: data.networkId.present ? data.networkId.value : this.networkId,
      ip: data.ip.present ? data.ip.value : this.ip,
      mac: data.mac.present ? data.mac.value : this.mac,
      hostname: data.hostname.present ? data.hostname.value : this.hostname,
      vendor: data.vendor.present ? data.vendor.value : this.vendor,
      model: data.model.present ? data.model.value : this.model,
      services: data.services.present ? data.services.value : this.services,
      sources: data.sources.present ? data.sources.value : this.sources,
      firstSeen: data.firstSeen.present ? data.firstSeen.value : this.firstSeen,
      lastSeen: data.lastSeen.present ? data.lastSeen.value : this.lastSeen,
      lastRttMs: data.lastRttMs.present ? data.lastRttMs.value : this.lastRttMs,
      rttHistory: data.rttHistory.present
          ? data.rttHistory.value
          : this.rttHistory,
      customName: data.customName.present
          ? data.customName.value
          : this.customName,
      notes: data.notes.present ? data.notes.value : this.notes,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Device(')
          ..write('networkId: $networkId, ')
          ..write('ip: $ip, ')
          ..write('mac: $mac, ')
          ..write('hostname: $hostname, ')
          ..write('vendor: $vendor, ')
          ..write('model: $model, ')
          ..write('services: $services, ')
          ..write('sources: $sources, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastRttMs: $lastRttMs, ')
          ..write('rttHistory: $rttHistory, ')
          ..write('customName: $customName, ')
          ..write('notes: $notes')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    networkId,
    ip,
    mac,
    hostname,
    vendor,
    model,
    services,
    sources,
    firstSeen,
    lastSeen,
    lastRttMs,
    rttHistory,
    customName,
    notes,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Device &&
          other.networkId == this.networkId &&
          other.ip == this.ip &&
          other.mac == this.mac &&
          other.hostname == this.hostname &&
          other.vendor == this.vendor &&
          other.model == this.model &&
          other.services == this.services &&
          other.sources == this.sources &&
          other.firstSeen == this.firstSeen &&
          other.lastSeen == this.lastSeen &&
          other.lastRttMs == this.lastRttMs &&
          other.rttHistory == this.rttHistory &&
          other.customName == this.customName &&
          other.notes == this.notes);
}

class DevicesCompanion extends UpdateCompanion<Device> {
  final Value<int> networkId;
  final Value<String> ip;
  final Value<String?> mac;
  final Value<String?> hostname;
  final Value<String?> vendor;
  final Value<String?> model;
  final Value<String> services;
  final Value<int> sources;
  final Value<DateTime?> firstSeen;
  final Value<DateTime?> lastSeen;
  final Value<int?> lastRttMs;
  final Value<String> rttHistory;
  final Value<String?> customName;
  final Value<String?> notes;
  final Value<int> rowid;
  const DevicesCompanion({
    this.networkId = const Value.absent(),
    this.ip = const Value.absent(),
    this.mac = const Value.absent(),
    this.hostname = const Value.absent(),
    this.vendor = const Value.absent(),
    this.model = const Value.absent(),
    this.services = const Value.absent(),
    this.sources = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.lastRttMs = const Value.absent(),
    this.rttHistory = const Value.absent(),
    this.customName = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DevicesCompanion.insert({
    required int networkId,
    required String ip,
    this.mac = const Value.absent(),
    this.hostname = const Value.absent(),
    this.vendor = const Value.absent(),
    this.model = const Value.absent(),
    this.services = const Value.absent(),
    this.sources = const Value.absent(),
    this.firstSeen = const Value.absent(),
    this.lastSeen = const Value.absent(),
    this.lastRttMs = const Value.absent(),
    this.rttHistory = const Value.absent(),
    this.customName = const Value.absent(),
    this.notes = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : networkId = Value(networkId),
       ip = Value(ip);
  static Insertable<Device> custom({
    Expression<int>? networkId,
    Expression<String>? ip,
    Expression<String>? mac,
    Expression<String>? hostname,
    Expression<String>? vendor,
    Expression<String>? model,
    Expression<String>? services,
    Expression<int>? sources,
    Expression<DateTime>? firstSeen,
    Expression<DateTime>? lastSeen,
    Expression<int>? lastRttMs,
    Expression<String>? rttHistory,
    Expression<String>? customName,
    Expression<String>? notes,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (networkId != null) 'network_id': networkId,
      if (ip != null) 'ip': ip,
      if (mac != null) 'mac': mac,
      if (hostname != null) 'hostname': hostname,
      if (vendor != null) 'vendor': vendor,
      if (model != null) 'model': model,
      if (services != null) 'services': services,
      if (sources != null) 'sources': sources,
      if (firstSeen != null) 'first_seen': firstSeen,
      if (lastSeen != null) 'last_seen': lastSeen,
      if (lastRttMs != null) 'last_rtt_ms': lastRttMs,
      if (rttHistory != null) 'rtt_history': rttHistory,
      if (customName != null) 'custom_name': customName,
      if (notes != null) 'notes': notes,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DevicesCompanion copyWith({
    Value<int>? networkId,
    Value<String>? ip,
    Value<String?>? mac,
    Value<String?>? hostname,
    Value<String?>? vendor,
    Value<String?>? model,
    Value<String>? services,
    Value<int>? sources,
    Value<DateTime?>? firstSeen,
    Value<DateTime?>? lastSeen,
    Value<int?>? lastRttMs,
    Value<String>? rttHistory,
    Value<String?>? customName,
    Value<String?>? notes,
    Value<int>? rowid,
  }) {
    return DevicesCompanion(
      networkId: networkId ?? this.networkId,
      ip: ip ?? this.ip,
      mac: mac ?? this.mac,
      hostname: hostname ?? this.hostname,
      vendor: vendor ?? this.vendor,
      model: model ?? this.model,
      services: services ?? this.services,
      sources: sources ?? this.sources,
      firstSeen: firstSeen ?? this.firstSeen,
      lastSeen: lastSeen ?? this.lastSeen,
      lastRttMs: lastRttMs ?? this.lastRttMs,
      rttHistory: rttHistory ?? this.rttHistory,
      customName: customName ?? this.customName,
      notes: notes ?? this.notes,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (networkId.present) {
      map['network_id'] = Variable<int>(networkId.value);
    }
    if (ip.present) {
      map['ip'] = Variable<String>(ip.value);
    }
    if (mac.present) {
      map['mac'] = Variable<String>(mac.value);
    }
    if (hostname.present) {
      map['hostname'] = Variable<String>(hostname.value);
    }
    if (vendor.present) {
      map['vendor'] = Variable<String>(vendor.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (services.present) {
      map['services'] = Variable<String>(services.value);
    }
    if (sources.present) {
      map['sources'] = Variable<int>(sources.value);
    }
    if (firstSeen.present) {
      map['first_seen'] = Variable<DateTime>(firstSeen.value);
    }
    if (lastSeen.present) {
      map['last_seen'] = Variable<DateTime>(lastSeen.value);
    }
    if (lastRttMs.present) {
      map['last_rtt_ms'] = Variable<int>(lastRttMs.value);
    }
    if (rttHistory.present) {
      map['rtt_history'] = Variable<String>(rttHistory.value);
    }
    if (customName.present) {
      map['custom_name'] = Variable<String>(customName.value);
    }
    if (notes.present) {
      map['notes'] = Variable<String>(notes.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DevicesCompanion(')
          ..write('networkId: $networkId, ')
          ..write('ip: $ip, ')
          ..write('mac: $mac, ')
          ..write('hostname: $hostname, ')
          ..write('vendor: $vendor, ')
          ..write('model: $model, ')
          ..write('services: $services, ')
          ..write('sources: $sources, ')
          ..write('firstSeen: $firstSeen, ')
          ..write('lastSeen: $lastSeen, ')
          ..write('lastRttMs: $lastRttMs, ')
          ..write('rttHistory: $rttHistory, ')
          ..write('customName: $customName, ')
          ..write('notes: $notes, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SettingsTable extends Settings with TableInfo<$SettingsTable, Setting> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueMeta = const VerificationMeta('value');
  @override
  late final GeneratedColumn<String> value = GeneratedColumn<String>(
    'value',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, value];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<Setting> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value')) {
      context.handle(
        _valueMeta,
        value.isAcceptableOrUnknown(data['value']!, _valueMeta),
      );
    } else if (isInserting) {
      context.missing(_valueMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  Setting map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return Setting(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      value: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value'],
      )!,
    );
  }

  @override
  $SettingsTable createAlias(String alias) {
    return $SettingsTable(attachedDatabase, alias);
  }
}

class Setting extends DataClass implements Insertable<Setting> {
  final String key;
  final String value;
  const Setting({required this.key, required this.value});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value'] = Variable<String>(value);
    return map;
  }

  SettingsCompanion toCompanion(bool nullToAbsent) {
    return SettingsCompanion(key: Value(key), value: Value(value));
  }

  factory Setting.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return Setting(
      key: serializer.fromJson<String>(json['key']),
      value: serializer.fromJson<String>(json['value']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'value': serializer.toJson<String>(value),
    };
  }

  Setting copyWith({String? key, String? value}) =>
      Setting(key: key ?? this.key, value: value ?? this.value);
  Setting copyWithCompanion(SettingsCompanion data) {
    return Setting(
      key: data.key.present ? data.key.value : this.key,
      value: data.value.present ? data.value.value : this.value,
    );
  }

  @override
  String toString() {
    return (StringBuffer('Setting(')
          ..write('key: $key, ')
          ..write('value: $value')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, value);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is Setting && other.key == this.key && other.value == this.value);
}

class SettingsCompanion extends UpdateCompanion<Setting> {
  final Value<String> key;
  final Value<String> value;
  final Value<int> rowid;
  const SettingsCompanion({
    this.key = const Value.absent(),
    this.value = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SettingsCompanion.insert({
    required String key,
    required String value,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       value = Value(value);
  static Insertable<Setting> custom({
    Expression<String>? key,
    Expression<String>? value,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (value != null) 'value': value,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? value,
    Value<int>? rowid,
  }) {
    return SettingsCompanion(
      key: key ?? this.key,
      value: value ?? this.value,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (value.present) {
      map['value'] = Variable<String>(value.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SettingsCompanion(')
          ..write('key: $key, ')
          ..write('value: $value, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$LocalStore extends GeneratedDatabase {
  _$LocalStore(QueryExecutor e) : super(e);
  $LocalStoreManager get managers => $LocalStoreManager(this);
  late final $NetworksTable networks = $NetworksTable(this);
  late final $DevicesTable devices = $DevicesTable(this);
  late final $SettingsTable settings = $SettingsTable(this);
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    networks,
    devices,
    settings,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'networks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('devices', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$NetworksTableCreateCompanionBuilder =
    NetworksCompanion Function({
      Value<int> id,
      required String key,
      required String cidr,
      Value<String?> gateway,
      Value<DateTime?> lastScanAt,
      Value<String?> ssid,
      Value<String?> remoteId,
    });
typedef $$NetworksTableUpdateCompanionBuilder =
    NetworksCompanion Function({
      Value<int> id,
      Value<String> key,
      Value<String> cidr,
      Value<String?> gateway,
      Value<DateTime?> lastScanAt,
      Value<String?> ssid,
      Value<String?> remoteId,
    });

final class $$NetworksTableReferences
    extends BaseReferences<_$LocalStore, $NetworksTable, Network> {
  $$NetworksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$DevicesTable, List<Device>> _devicesRefsTable(
    _$LocalStore db,
  ) => MultiTypedResultKey.fromTable(
    db.devices,
    aliasName: 'networks__id__devices__network_id',
  );

  $$DevicesTableProcessedTableManager get devicesRefs {
    final manager = $$DevicesTableTableManager(
      $_db,
      $_db.devices,
    ).filter((f) => f.networkId.id.sqlEquals($_itemColumn<int>('id')!));

    final cache = $_typedResult.readTableOrNull(_devicesRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$NetworksTableFilterComposer
    extends Composer<_$LocalStore, $NetworksTable> {
  $$NetworksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cidr => $composableBuilder(
    column: $table.cidr,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get gateway => $composableBuilder(
    column: $table.gateway,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get ssid => $composableBuilder(
    column: $table.ssid,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> devicesRefs(
    Expression<bool> Function($$DevicesTableFilterComposer f) f,
  ) {
    final $$DevicesTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.networkId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableFilterComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NetworksTableOrderingComposer
    extends Composer<_$LocalStore, $NetworksTable> {
  $$NetworksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<int> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cidr => $composableBuilder(
    column: $table.cidr,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get gateway => $composableBuilder(
    column: $table.gateway,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get ssid => $composableBuilder(
    column: $table.ssid,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get remoteId => $composableBuilder(
    column: $table.remoteId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$NetworksTableAnnotationComposer
    extends Composer<_$LocalStore, $NetworksTable> {
  $$NetworksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<int> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get cidr =>
      $composableBuilder(column: $table.cidr, builder: (column) => column);

  GeneratedColumn<String> get gateway =>
      $composableBuilder(column: $table.gateway, builder: (column) => column);

  GeneratedColumn<DateTime> get lastScanAt => $composableBuilder(
    column: $table.lastScanAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get ssid =>
      $composableBuilder(column: $table.ssid, builder: (column) => column);

  GeneratedColumn<String> get remoteId =>
      $composableBuilder(column: $table.remoteId, builder: (column) => column);

  Expression<T> devicesRefs<T extends Object>(
    Expression<T> Function($$DevicesTableAnnotationComposer a) f,
  ) {
    final $$DevicesTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.devices,
      getReferencedColumn: (t) => t.networkId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DevicesTableAnnotationComposer(
            $db: $db,
            $table: $db.devices,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$NetworksTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $NetworksTable,
          Network,
          $$NetworksTableFilterComposer,
          $$NetworksTableOrderingComposer,
          $$NetworksTableAnnotationComposer,
          $$NetworksTableCreateCompanionBuilder,
          $$NetworksTableUpdateCompanionBuilder,
          (Network, $$NetworksTableReferences),
          Network,
          PrefetchHooks Function({bool devicesRefs})
        > {
  $$NetworksTableTableManager(_$LocalStore db, $NetworksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$NetworksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$NetworksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$NetworksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                Value<String> key = const Value.absent(),
                Value<String> cidr = const Value.absent(),
                Value<String?> gateway = const Value.absent(),
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<String?> ssid = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
              }) => NetworksCompanion(
                id: id,
                key: key,
                cidr: cidr,
                gateway: gateway,
                lastScanAt: lastScanAt,
                ssid: ssid,
                remoteId: remoteId,
              ),
          createCompanionCallback:
              ({
                Value<int> id = const Value.absent(),
                required String key,
                required String cidr,
                Value<String?> gateway = const Value.absent(),
                Value<DateTime?> lastScanAt = const Value.absent(),
                Value<String?> ssid = const Value.absent(),
                Value<String?> remoteId = const Value.absent(),
              }) => NetworksCompanion.insert(
                id: id,
                key: key,
                cidr: cidr,
                gateway: gateway,
                lastScanAt: lastScanAt,
                ssid: ssid,
                remoteId: remoteId,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$NetworksTable, Network>(table),
                  $$NetworksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({devicesRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (devicesRefs) db.devices],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (devicesRefs)
                    await $_getPrefetchedData<Network, $NetworksTable, Device>(
                      currentTable: table,
                      referencedTable: $$NetworksTableReferences
                          ._devicesRefsTable(db),
                      managerFromTypedResult: (p0) =>
                          $$NetworksTableReferences(db, table, p0).devicesRefs,
                      referencedItemsForCurrentItem: (item, referencedItems) =>
                          referencedItems.where((e) => e.networkId == item.id),
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$NetworksTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $NetworksTable,
      Network,
      $$NetworksTableFilterComposer,
      $$NetworksTableOrderingComposer,
      $$NetworksTableAnnotationComposer,
      $$NetworksTableCreateCompanionBuilder,
      $$NetworksTableUpdateCompanionBuilder,
      (Network, $$NetworksTableReferences),
      Network,
      PrefetchHooks Function({bool devicesRefs})
    >;
typedef $$DevicesTableCreateCompanionBuilder =
    DevicesCompanion Function({
      required int networkId,
      required String ip,
      Value<String?> mac,
      Value<String?> hostname,
      Value<String?> vendor,
      Value<String?> model,
      Value<String> services,
      Value<int> sources,
      Value<DateTime?> firstSeen,
      Value<DateTime?> lastSeen,
      Value<int?> lastRttMs,
      Value<String> rttHistory,
      Value<String?> customName,
      Value<String?> notes,
      Value<int> rowid,
    });
typedef $$DevicesTableUpdateCompanionBuilder =
    DevicesCompanion Function({
      Value<int> networkId,
      Value<String> ip,
      Value<String?> mac,
      Value<String?> hostname,
      Value<String?> vendor,
      Value<String?> model,
      Value<String> services,
      Value<int> sources,
      Value<DateTime?> firstSeen,
      Value<DateTime?> lastSeen,
      Value<int?> lastRttMs,
      Value<String> rttHistory,
      Value<String?> customName,
      Value<String?> notes,
      Value<int> rowid,
    });

final class $$DevicesTableReferences
    extends BaseReferences<_$LocalStore, $DevicesTable, Device> {
  $$DevicesTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $NetworksTable _networkIdTable(_$LocalStore db) =>
      db.networks.createAlias('devices__network_id__networks__id');

  $$NetworksTableProcessedTableManager get networkId {
    final $_column = $_itemColumn<int>('network_id')!;

    final manager = $$NetworksTableTableManager(
      $_db,
      $_db.networks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_networkIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$DevicesTableFilterComposer
    extends Composer<_$LocalStore, $DevicesTable> {
  $$DevicesTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get ip => $composableBuilder(
    column: $table.ip,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mac => $composableBuilder(
    column: $table.mac,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get vendor => $composableBuilder(
    column: $table.vendor,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get services => $composableBuilder(
    column: $table.services,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get sources => $composableBuilder(
    column: $table.sources,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get lastRttMs => $composableBuilder(
    column: $table.lastRttMs,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get rttHistory => $composableBuilder(
    column: $table.rttHistory,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnFilters(column),
  );

  $$NetworksTableFilterComposer get networkId {
    final $$NetworksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.networkId,
      referencedTable: $db.networks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NetworksTableFilterComposer(
            $db: $db,
            $table: $db.networks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableOrderingComposer
    extends Composer<_$LocalStore, $DevicesTable> {
  $$DevicesTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get ip => $composableBuilder(
    column: $table.ip,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mac => $composableBuilder(
    column: $table.mac,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hostname => $composableBuilder(
    column: $table.hostname,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get vendor => $composableBuilder(
    column: $table.vendor,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get services => $composableBuilder(
    column: $table.services,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get sources => $composableBuilder(
    column: $table.sources,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get firstSeen => $composableBuilder(
    column: $table.firstSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<DateTime> get lastSeen => $composableBuilder(
    column: $table.lastSeen,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get lastRttMs => $composableBuilder(
    column: $table.lastRttMs,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get rttHistory => $composableBuilder(
    column: $table.rttHistory,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get notes => $composableBuilder(
    column: $table.notes,
    builder: (column) => ColumnOrderings(column),
  );

  $$NetworksTableOrderingComposer get networkId {
    final $$NetworksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.networkId,
      referencedTable: $db.networks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NetworksTableOrderingComposer(
            $db: $db,
            $table: $db.networks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableAnnotationComposer
    extends Composer<_$LocalStore, $DevicesTable> {
  $$DevicesTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get ip =>
      $composableBuilder(column: $table.ip, builder: (column) => column);

  GeneratedColumn<String> get mac =>
      $composableBuilder(column: $table.mac, builder: (column) => column);

  GeneratedColumn<String> get hostname =>
      $composableBuilder(column: $table.hostname, builder: (column) => column);

  GeneratedColumn<String> get vendor =>
      $composableBuilder(column: $table.vendor, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<String> get services =>
      $composableBuilder(column: $table.services, builder: (column) => column);

  GeneratedColumn<int> get sources =>
      $composableBuilder(column: $table.sources, builder: (column) => column);

  GeneratedColumn<DateTime> get firstSeen =>
      $composableBuilder(column: $table.firstSeen, builder: (column) => column);

  GeneratedColumn<DateTime> get lastSeen =>
      $composableBuilder(column: $table.lastSeen, builder: (column) => column);

  GeneratedColumn<int> get lastRttMs =>
      $composableBuilder(column: $table.lastRttMs, builder: (column) => column);

  GeneratedColumn<String> get rttHistory => $composableBuilder(
    column: $table.rttHistory,
    builder: (column) => column,
  );

  GeneratedColumn<String> get customName => $composableBuilder(
    column: $table.customName,
    builder: (column) => column,
  );

  GeneratedColumn<String> get notes =>
      $composableBuilder(column: $table.notes, builder: (column) => column);

  $$NetworksTableAnnotationComposer get networkId {
    final $$NetworksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.networkId,
      referencedTable: $db.networks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$NetworksTableAnnotationComposer(
            $db: $db,
            $table: $db.networks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$DevicesTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $DevicesTable,
          Device,
          $$DevicesTableFilterComposer,
          $$DevicesTableOrderingComposer,
          $$DevicesTableAnnotationComposer,
          $$DevicesTableCreateCompanionBuilder,
          $$DevicesTableUpdateCompanionBuilder,
          (Device, $$DevicesTableReferences),
          Device,
          PrefetchHooks Function({bool networkId})
        > {
  $$DevicesTableTableManager(_$LocalStore db, $DevicesTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DevicesTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DevicesTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DevicesTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<int> networkId = const Value.absent(),
                Value<String> ip = const Value.absent(),
                Value<String?> mac = const Value.absent(),
                Value<String?> hostname = const Value.absent(),
                Value<String?> vendor = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String> services = const Value.absent(),
                Value<int> sources = const Value.absent(),
                Value<DateTime?> firstSeen = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int?> lastRttMs = const Value.absent(),
                Value<String> rttHistory = const Value.absent(),
                Value<String?> customName = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion(
                networkId: networkId,
                ip: ip,
                mac: mac,
                hostname: hostname,
                vendor: vendor,
                model: model,
                services: services,
                sources: sources,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                lastRttMs: lastRttMs,
                rttHistory: rttHistory,
                customName: customName,
                notes: notes,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required int networkId,
                required String ip,
                Value<String?> mac = const Value.absent(),
                Value<String?> hostname = const Value.absent(),
                Value<String?> vendor = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<String> services = const Value.absent(),
                Value<int> sources = const Value.absent(),
                Value<DateTime?> firstSeen = const Value.absent(),
                Value<DateTime?> lastSeen = const Value.absent(),
                Value<int?> lastRttMs = const Value.absent(),
                Value<String> rttHistory = const Value.absent(),
                Value<String?> customName = const Value.absent(),
                Value<String?> notes = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DevicesCompanion.insert(
                networkId: networkId,
                ip: ip,
                mac: mac,
                hostname: hostname,
                vendor: vendor,
                model: model,
                services: services,
                sources: sources,
                firstSeen: firstSeen,
                lastSeen: lastSeen,
                lastRttMs: lastRttMs,
                rttHistory: rttHistory,
                customName: customName,
                notes: notes,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DevicesTable, Device>(table),
                  $$DevicesTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({networkId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (networkId) {
                      state =
                          state.withJoin(
                                currentTable: table,
                                currentColumn: table.networkId,
                                referencedTable: $$DevicesTableReferences
                                    ._networkIdTable(db),
                                referencedColumn: $$DevicesTableReferences
                                    ._networkIdTable(db)
                                    .id,
                              )
                              as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$DevicesTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $DevicesTable,
      Device,
      $$DevicesTableFilterComposer,
      $$DevicesTableOrderingComposer,
      $$DevicesTableAnnotationComposer,
      $$DevicesTableCreateCompanionBuilder,
      $$DevicesTableUpdateCompanionBuilder,
      (Device, $$DevicesTableReferences),
      Device,
      PrefetchHooks Function({bool networkId})
    >;
typedef $$SettingsTableCreateCompanionBuilder =
    SettingsCompanion Function({
      required String key,
      required String value,
      Value<int> rowid,
    });
typedef $$SettingsTableUpdateCompanionBuilder =
    SettingsCompanion Function({
      Value<String> key,
      Value<String> value,
      Value<int> rowid,
    });

class $$SettingsTableFilterComposer
    extends Composer<_$LocalStore, $SettingsTable> {
  $$SettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SettingsTableOrderingComposer
    extends Composer<_$LocalStore, $SettingsTable> {
  $$SettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get value => $composableBuilder(
    column: $table.value,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SettingsTableAnnotationComposer
    extends Composer<_$LocalStore, $SettingsTable> {
  $$SettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get value =>
      $composableBuilder(column: $table.value, builder: (column) => column);
}

class $$SettingsTableTableManager
    extends
        RootTableManager<
          _$LocalStore,
          $SettingsTable,
          Setting,
          $$SettingsTableFilterComposer,
          $$SettingsTableOrderingComposer,
          $$SettingsTableAnnotationComposer,
          $$SettingsTableCreateCompanionBuilder,
          $$SettingsTableUpdateCompanionBuilder,
          (Setting, BaseReferences<_$LocalStore, $SettingsTable, Setting>),
          Setting,
          PrefetchHooks Function()
        > {
  $$SettingsTableTableManager(_$LocalStore db, $SettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> value = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion(key: key, value: value, rowid: rowid),
          createCompanionCallback:
              ({
                required String key,
                required String value,
                Value<int> rowid = const Value.absent(),
              }) => SettingsCompanion.insert(
                key: key,
                value: value,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SettingsTable, Setting>(table),
                  BaseReferences<_$LocalStore, $SettingsTable, Setting>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$LocalStore,
      $SettingsTable,
      Setting,
      $$SettingsTableFilterComposer,
      $$SettingsTableOrderingComposer,
      $$SettingsTableAnnotationComposer,
      $$SettingsTableCreateCompanionBuilder,
      $$SettingsTableUpdateCompanionBuilder,
      (Setting, BaseReferences<_$LocalStore, $SettingsTable, Setting>),
      Setting,
      PrefetchHooks Function()
    >;

class $LocalStoreManager {
  final _$LocalStore _db;
  $LocalStoreManager(this._db);
  $$NetworksTableTableManager get networks =>
      $$NetworksTableTableManager(_db, _db.networks);
  $$DevicesTableTableManager get devices =>
      $$DevicesTableTableManager(_db, _db.devices);
  $$SettingsTableTableManager get settings =>
      $$SettingsTableTableManager(_db, _db.settings);
}
