import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/services/local_storage.dart';
import 'package:pingduck_app/services/scan_quota.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late DateTime now;
  Map<String, dynamic>? server;  // null = unreachable

  ServerScanQuota quota() => ServerScanQuota(store, () async {
        final answer = server;
        if (answer == null) throw Exception('offline');
        return answer;
      }, clock: () => now);

  setUp(() {
    store = memoryStore();
    now = DateTime.utc(2026, 10, 7, 15);
    server = null;
  });
  tearDown(() => store.close());

  test('offline before the server ever answered: Free limit of 3 a day', () async {
    final q = quota();
    expect((await q.claim()).remaining, 2);
    expect((await q.claim()).remaining, 1);
    expect((await q.claim()).remaining, 0);
    expect((await q.claim()).allowed, isFalse);
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

  test('the allowance resets at midnight UTC', () async {
    final q = quota();
    for (var i = 0; i < 3; i++) {
      await q.claim();
    }
    expect((await q.claim()).allowed, isFalse);
    now = DateTime.utc(2026, 10, 8, 0, 1);
    expect((await q.claim()).remaining, 2);
  });

  test('nextQuotaReset is the next UTC midnight', () {
    expect(nextQuotaReset(DateTime.utc(2026, 10, 7, 23, 59)).toUtc(), DateTime.utc(2026, 10, 8));
    expect(nextQuotaReset(DateTime.utc(2026, 12, 31, 12)).toUtc(), DateTime.utc(2027, 1, 1));
  });
}
