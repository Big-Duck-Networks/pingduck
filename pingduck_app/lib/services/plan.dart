import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/auth/account_auth.dart';
import '../features/auth/session.dart';
import '../features/scanner/application/scan_controller.dart';
import 'local_storage.dart';
import 'scan_quota.dart';

/// The account's plan, as the server's `my_plan()` answers it (a row of the
/// `plans` table). Billing never decides this on the device.
class Plan {
  const Plan({required this.code, required this.name, this.dailyScanLimit, this.maxMonitoredNetworks = 0});

  factory Plan.fromRow(Map<String, dynamic> row) => Plan(
    code: row['code'] as String? ?? 'free',
    name: row['name'] as String? ?? 'Free',
    dailyScanLimit: (row['daily_scan_limit'] as num?)?.toInt(),
    maxMonitoredNetworks: (row['max_monitored_networks'] as num?)?.toInt() ?? 0,
  );

  static const free = Plan(code: 'free', name: 'Free', dailyScanLimit: 3);
  static const premium = Plan(code: 'premium', name: 'Premium', maxMonitoredNetworks: 2);

  final String code;
  final String name;

  /// Null when scans are unlimited.
  final int? dailyScanLimit;
  final int maxMonitoredNetworks;

  bool get isPaid => code != 'free';
}

abstract interface class PlanRepository {
  Future<Plan> myPlan();
}

class SupabasePlanRepository implements PlanRepository {
  SupabasePlanRepository(this._store);

  final LocalStore _store;

  @override
  Future<Plan> myPlan() async {
    final answer = await (await signedInClient()).rpc('my_plan');
    final row = answer is List ? (answer.isEmpty ? null : answer.first) : answer;
    final plan = row is Map ? Plan.fromRow(Map<String, dynamic>.from(row)) : Plan.free;
    // Same cache claim_scan writes, so an offline launch knows the plan.
    await _store.setSetting(isPremiumKey, plan.isPaid ? '1' : '0');
    return plan;
  }
}

final planRepositoryProvider = Provider<PlanRepository>((ref) => SupabasePlanRepository(ref.read(localStoreProvider)));

/// The current plan. Refreshed on launch, resume, sign-in or sign-out, and
/// after a purchase or restore. Offline, falls back to the last server answer.
class CurrentPlan extends AsyncNotifier<Plan> {
  @override
  Future<Plan> build() async {
    ref.listen(accountEmailProvider, (prev, next) {
      if (prev?.value != next.value) refresh();
    });
    return _fetch();
  }

  Future<Plan> _fetch() async {
    try {
      return await ref.read(planRepositoryProvider).myPlan();
    } catch (_) {
      return await isPremiumUser(ref.read(localStoreProvider)) ? Plan.premium : Plan.free;
    }
  }

  Future<void> refresh() async => state = AsyncData(await _fetch());

  /// After a purchase the webhook needs a moment to write the entitlement.
  /// Polls until the plan is paid; false if it isn't by [timeout].
  Future<bool> waitForPaid({
    Duration timeout = const Duration(seconds: 30),
    Duration every = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (true) {
      try {
        final plan = await ref.read(planRepositoryProvider).myPlan();
        state = AsyncData(plan);
        if (plan.isPaid) return true;
      } catch (_) {
        // Keep polling until the deadline.
      }
      if (DateTime.now().add(every).isAfter(deadline)) return false;
      await Future<void>.delayed(every);
    }
  }
}

final currentPlanProvider = AsyncNotifierProvider<CurrentPlan, Plan>(CurrentPlan.new);
