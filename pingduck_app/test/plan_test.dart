import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/services/local_storage.dart';
import 'package:pingduck_app/services/plan.dart';
import 'package:pingduck_app/services/scan_quota.dart';

import 'fakes.dart';

void main() {
  late LocalStore store;
  late FakePlanRepository repo;
  late FakeAuth auth;

  ProviderContainer container() {
    final c = ProviderContainer(overrides: [
      localStoreProvider.overrideWithValue(store),
      planRepositoryProvider.overrideWithValue(repo),
      accountAuthProvider.overrideWithValue(auth),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  setUp(() {
    store = memoryStore();
    repo = FakePlanRepository();
    auth = FakeAuth();
  });

  test('a plans row maps to a Plan', () {
    final plan = Plan.fromRow({
      'code': 'premium',
      'name': 'Premium',
      'daily_scan_limit': null,
      'max_monitored_networks': 2,
    });
    expect(plan.isPaid, isTrue);
    expect(plan.dailyScanLimit, isNull);
    expect(plan.maxMonitoredNetworks, 2);
    expect(Plan.free.isPaid, isFalse);
  });

  test('the current plan comes from the repository', () async {
    repo = FakePlanRepository([Plan.premium]);
    expect((await container().read(currentPlanProvider.future)).code, 'premium');
  });

  test('offline, the plan falls back to the last server answer', () async {
    repo.error = Exception('offline');
    await store.setSetting(isPremiumKey, '1');
    expect((await container().read(currentPlanProvider.future)).isPaid, isTrue);

    await store.setSetting(isPremiumKey, '0');
    final c = container();
    expect((await c.read(currentPlanProvider.future)).isPaid, isFalse);
  });

  test('waitForPaid polls until the webhook has written the entitlement', () async {
    repo = FakePlanRepository([Plan.free, Plan.free, Plan.free, Plan.premium]);
    final c = container();
    await c.read(currentPlanProvider.future);
    final paid = await c
        .read(currentPlanProvider.notifier)
        .waitForPaid(timeout: const Duration(seconds: 1), every: const Duration(milliseconds: 10));
    expect(paid, isTrue);
    expect(c.read(currentPlanProvider).value?.code, 'premium');
  });

  test('waitForPaid gives up after the timeout', () async {
    final c = container();
    await c.read(currentPlanProvider.future);
    final paid = await c
        .read(currentPlanProvider.notifier)
        .waitForPaid(timeout: const Duration(milliseconds: 50), every: const Duration(milliseconds: 10));
    expect(paid, isFalse);
    expect(repo.calls, greaterThan(2));
  });
}
