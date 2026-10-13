import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/features/scanner/domain/remote_device.dart';
import 'package:pingduck_app/services/local_storage.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late int net;

  setUp(() async {
    store = memoryStore();
    net = await store.networkFor(key: 'k', cidr: '10.42.0.0/24', gateway: '10.42.0.1');
  });
  tearDown(() => store.close());

  Future<DiscoveredDevice?> device(String ip) async =>
      (await store.devicesOf(net)).where((d) => d.ip == ip).firstOrNull;

  test('fills the MAC and missing names by IP, keeping the user\'s own', () async {
    await store.saveDevices(net, [
      const DiscoveredDevice(
        ip: '10.42.0.5',
        hostname: 'nas.local',
        vendor: 'Private (randomized MAC)',
        sources: {DiscoverySource.icmp},
        customName: 'Big NAS',
        notes: 'rack',
      ),
    ]);
    final written = await store.mergeRemoteDevices(net, [
      RemoteDevice(mac: 'AA:BB:CC:00:00:05', ip: '10.42.0.5', hostname: 'other', vendor: 'Synology', model: 'DS920+'),
    ]);

    expect(written, 1);
    final d = (await device('10.42.0.5'))!;
    expect(d.mac, 'aa:bb:cc:00:00:05');
    expect(d.hostname, 'nas.local', reason: 'a name the phone found wins');
    expect(d.vendor, 'Synology', reason: 'a randomized-MAC placeholder loses');
    expect(d.model, 'DS920+');
    expect(d.customName, 'Big NAS');
    expect(d.notes, 'rack');
    expect(d.sources, {DiscoverySource.icmp, DiscoverySource.agent});
  });

  test('adds devices only the agent sees', () async {
    final seen = DateTime(2026, 10, 12, 9);
    await store.mergeRemoteDevices(net, [
      RemoteDevice(mac: 'aa:bb:cc:00:00:09', ip: '10.42.0.9', vendor: 'Espressif', isKnown: true, lastSeenAt: seen),
    ]);

    final d = (await device('10.42.0.9'))!;
    expect(d.sources, {DiscoverySource.agent});
    expect(d.vendor, 'Espressif');
    expect(d.isKnown, isTrue);
    expect(d.lastSeen, seen);
    expect(d.isOnline, isFalse);
  });

  test('a MAC cached under another IP is not duplicated', () async {
    await store.saveDevices(net, [const DiscoveredDevice(ip: '10.42.0.20', mac: 'aa:bb:cc:00:00:20')]);
    final written = await store.mergeRemoteDevices(net, [RemoteDevice(mac: 'AA:BB:CC:00:00:20', ip: '10.42.0.21')]);

    expect(written, 0);
    expect((await store.devicesOf(net)).map((d) => d.ip), ['10.42.0.20']);
  });

  test('devices without an IP are skipped', () async {
    expect(await store.mergeRemoteDevices(net, [const RemoteDevice(mac: 'aa:bb:cc:00:00:30')]), 0);
  });

  test('the known flag follows the server and survives a scan', () async {
    await store.saveDevices(net, [const DiscoveredDevice(ip: '10.42.0.5')]);
    await store.mergeRemoteDevices(net, [const RemoteDevice(mac: 'aa:bb:cc:00:00:05', ip: '10.42.0.5', isKnown: true)]);
    final cached = (await device('10.42.0.5'))!;
    expect(cached.isKnown, isTrue);

    // A scan report never carries the flag; merging it must not clear it.
    final scanned = cached.merge(const DiscoveredDevice(ip: '10.42.0.5', rttMs: 3, isOnline: true));
    expect(scanned.isKnown, isTrue);

    await store.setKnown(net, 'AA:BB:CC:00:00:05', false);
    expect((await device('10.42.0.5'))!.isKnown, isFalse);
  });

  test('linkedNetworks lists only networks with a monitoring unit', () async {
    final other = await store.networkFor(key: 'k2', cidr: '192.168.1.0/24');
    await store.setRemoteId(other, 'remote-2');
    expect(await store.linkedNetworks(), [(id: other, remoteId: 'remote-2')]);
  });

  test('RemoteDevice.fromRow reads PostgREST rows', () {
    final d = RemoteDevice.fromRow({
      'mac': 'aa:bb:cc:00:00:05',
      'ip': '10.42.0.5/32',
      'hostname': null,
      'vendor': 'TP-Link',
      'model': null,
      'is_known': true,
      'first_seen_at': '2026-10-12T14:38:07.65875+00:00',
      'last_seen_at': '2026-10-12T14:40:05+00:00',
    })!;
    expect(d.ip, '10.42.0.5');
    expect(d.isKnown, isTrue);
    expect(d.lastSeenAt!.toUtc(), DateTime.utc(2026, 10, 12, 14, 40, 5));
    expect(RemoteDevice.fromRow({'mac': null}), isNull);
  });

  test('opening after an older build lowered the version does not add columns twice', () async {
    final dir = await Directory.systemTemp.createTemp('pingduck_cache');
    addTearDown(() => dir.delete(recursive: true));
    final file = File('${dir.path}/pingduck.sqlite');

    // A v4 database, then an older (v3) build opened it: the version drops,
    // the is_known column stays.
    final v4 = LocalStore(NativeDatabase(file));
    await v4.setSetting('onboarded', '1');
    await v4.customStatement('PRAGMA user_version = 3');
    await v4.close();

    final reopened = LocalStore(NativeDatabase(file));
    addTearDown(reopened.close);
    expect(await reopened.setting('onboarded'), '1');
    final version = await reopened.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), reopened.schemaVersion);
  });
}
