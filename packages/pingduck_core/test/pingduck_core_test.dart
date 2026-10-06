// Exercises the real native library over FFI. Needs a built libpingduck on
// the library search path (e.g. core/build/bin/Release on Windows via PATH)
// and a LAN; skipped otherwise.
//
//   PATH="$PWD/../../core/build-test/bin/Release:$PATH" flutter test
@Tags(['native'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_core/pingduck_core.dart';

void main() {
  PingDuckCore? core;
  try {
    core = PingDuckCore.instance;
    core.version;
  } catch (_) {
    core = null;
  }
  final skip = core == null ? 'libpingduck not found on the library path' : null;

  test('version and default interface', () {
    expect(core!.version, isNotEmpty);
    final iface = core.defaultInterface();
    expect(iface, isNotNull);
    expect(iface!.cidr, matches(RegExp(r'^\d+\.\d+\.\d+\.\d+/\d+$')));
  }, skip: skip);

  test('scan streams upserts and completes with the device count', () async {
    final session = core!.scan(timeout: const Duration(seconds: 2));
    final seen = <String, PdDevice>{};
    await for (final d in session.devices) {
      seen[d.ip] = d;
    }
    final outcome = await session.done;
    expect(outcome.cancelled, isFalse);
    expect(outcome.deviceCount, seen.length);
    expect(seen, isNotEmpty);
    expect(seen.values.where((d) => d.sources & PD_SRC_ICMP != 0), isNotEmpty);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test('cancel mid-scan ends the stream and reports cancelled', () async {
    final session = core!.scan(timeout: const Duration(seconds: 5));
    final sw = Stopwatch()..start();
    Future.delayed(const Duration(milliseconds: 300), session.cancel);
    var count = 0;
    await for (final _ in session.devices) {
      count++;
    }
    final outcome = await session.done;
    expect(outcome.cancelled, isTrue);
    expect(sw.elapsed, lessThan(const Duration(seconds: 3)));
    expect(count, greaterThanOrEqualTo(0));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test('a scan after a cancel still works', () async {
    final session = core!.mdns(timeout: const Duration(seconds: 2));
    final devices = await session.devices.toList();
    final outcome = await session.done;
    expect(outcome.cancelled, isFalse);
    expect(outcome.deviceCount, devices.length);
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));

  test('many short sessions do not leak or crash', () async {
    for (var i = 0; i < 20; i++) {
      final s = core!.ssdp(timeout: const Duration(milliseconds: 200));
      if (i.isEven) s.cancel();
      await s.devices.drain<void>();
      await s.done;
    }
  }, skip: skip, timeout: const Timeout(Duration(seconds: 60)));

  test('loadOui from bytes', () async {
    final csv = utf8.encode('Registry,Assignment,Organization Name\nMA-L,A4C3F0,Intel Corporate\n');
    expect(await core!.loadOui(Uint8List.fromList(csv)), 1);
  }, skip: skip);

  test('diagnostics: ping, ports, reverse lookup', () async {
    final gw = core!.defaultInterface()!.gateway!;
    expect(await core.ping(gw), isNotNull);
    expect(await core.ping('192.0.2.1', timeout: const Duration(milliseconds: 300)), isNull);
    expect(await core.openPorts(gw, [80, 443, 1]), isA<Set<int>>());
    await core.reverseLookup(gw);  // may legitimately be null
    expect(() => core!.ping('bogus'), throwsA(isA<PingDuckException>()));
  }, skip: skip, timeout: const Timeout(Duration(seconds: 30)));
}
