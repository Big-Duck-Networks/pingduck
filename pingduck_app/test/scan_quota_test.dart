import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/services/local_storage.dart';
import 'package:pingduck_app/services/scan_quota.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late DateTime now;
  Map<String, dynamic>? server;  // null = unreachable
  final asked = <bool>[]; // the automatic flag of each server call

  ServerScanQuota quota() => ServerScanQuota(store, ({required bool automatic}) async {
        asked.add(automatic);
        final answer = server;
        if (answer == null) throw Exception('offline');
        return answer;
      }, clock: () => now);

  setUp(() {
    store = memoryStore();
    now = DateTime.utc(2026, 10, 7, 15);
    server = null;
    asked.clear();
  });
  tearDown(() => store.close());

  test('offline before the server ever answered: no scans, so clearing data gives none', () async {
    final r = await quota().claim();
    expect(r.allowed, isFalse);
    expect(r.unverified, isTrue);
    expect(await quota().claimAutomatic(), isFalse);
  });

  test('offline after a Free answer: counts on locally from it', () async {
    server = {'allowed': true, 'remaining': 2, 'limit': 3};
    await quota().claim();
    server = null;
    final q = quota();
    expect((await q.claim()).remaining, 1);
    expect((await q.claim()).remaining, 0);
    final r = await q.claim();
    expect(r.allowed, isFalse);
    expect(r.unverified, isFalse);
  });

  test('the server answer wins and is mirrored for offline use', () async {
    server = {'allowed': true, 'remaining': 0, 'limit': 3};
    expect((await quota().claim()).allowed, isTrue);
    server = null;
    expect((await quota().claim()).allowed, isFalse, reason: 'used 3 of 3 per the server');
  });

  test('a server refusal is passed through', () async {
    server = {'allowed': false, 'remaining': 0, 'limit': 3};
    expect((await quota().claim()).allowed, isFalse);
  });

  test('unlimited plans stay unlimited offline', () async {
    server = {'allowed': true, 'remaining': null, 'limit': null};
    await quota().claim();
    server = null;
    for (var i = 0; i < 10; i++) {
      final r = await quota().claim();
      expect(r.allowed, isTrue);
      expect(r.limit, isNull);
    }
  });

  test('offline, the allowance resets at midnight UTC', () async {
    server = {'allowed': true, 'remaining': 2, 'limit': 3};
    await quota().claim();
    server = null;
    final q = quota();
    for (var i = 0; i < 2; i++) {
      await q.claim();
    }
    expect((await q.claim()).allowed, isFalse);
    now = DateTime.utc(2026, 10, 8, 0, 1);
    expect((await q.claim()).remaining, 2);
  });

  test('automatic scans ask the server, which decides', () async {
    server = {'allowed': false, 'remaining': 3, 'limit': 3};
    expect(await quota().claimAutomatic(), isFalse);
    server = {'allowed': true, 'remaining': 3, 'limit': 3};
    expect(await quota().claimAutomatic(), isTrue);
    expect(asked, [true, true]);
  });

  test('offline, automatic scans are free but at most one per 30 minutes on Free', () async {
    server = {'allowed': true, 'remaining': 3, 'limit': 3};
    expect(await quota().claimAutomatic(), isTrue);
    server = null;
    final q = quota();
    now = now.add(const Duration(minutes: 29));
    expect(await q.claimAutomatic(), isFalse);
    now = now.add(const Duration(minutes: 1));
    expect(await q.claimAutomatic(), isTrue);
    expect((await q.claim()).remaining, 2, reason: 'automatic scans do not use the daily allowance');
  });

  test('automatic scans are not rate-limited on unlimited plans', () async {
    server = {'allowed': true, 'remaining': null, 'limit': null};
    await quota().claim();
    for (var i = 0; i < 5; i++) {
      expect(await quota().claimAutomatic(), isTrue);
    }
  });

  test('nextQuotaReset is the next UTC midnight', () {
    expect(nextQuotaReset(DateTime.utc(2026, 10, 7, 23, 59)).toUtc(), DateTime.utc(2026, 10, 8));
    expect(nextQuotaReset(DateTime.utc(2026, 12, 31, 12)).toUtc(), DateTime.utc(2027, 1, 1));
  });

  test('isPremiumUser defaults to false and updates when unlimited plan claimed', () async {
    expect(await isPremiumUser(store), isFalse);
    server = {'allowed': true, 'remaining': null, 'limit': null};
    await quota().claim();
    expect(await isPremiumUser(store), isTrue);
  });

  test('auto-scan on launch neither makes a user Premium nor lifts the automatic limit', () async {
    await setAutoScanOnLaunch(store, true);
    expect(await isPremiumUser(store), isFalse);
    server = {'allowed': true, 'remaining': 3, 'limit': 3};
    await quota().claim();
    server = null;
    final q = quota();
    expect(await q.claimAutomatic(), isTrue);
    expect(await q.claimAutomatic(), isFalse);
  });

  test('a limited plan from the server clears a cached Premium', () async {
    server = {'allowed': true, 'remaining': null, 'limit': null};
    await quota().claim();
    expect(await isPremiumUser(store), isTrue);
    server = {'allowed': true, 'remaining': 2, 'limit': 3};
    await quota().claim();
    expect(await isPremiumUser(store), isFalse);
  });
}
