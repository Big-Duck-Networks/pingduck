import 'dart:async';

import 'local_storage.dart';

/// Answer to "may this install run another scan today?".
class QuotaResult {
  const QuotaResult({required this.allowed, this.remaining, this.limit});

  final bool allowed;

  /// Scans left today; null when the plan is unlimited.
  final int? remaining;

  /// Daily limit; null when the plan is unlimited.
  final int? limit;
}

abstract interface class ScanQuota {
  /// A scan the user asked for. Counts against the daily limit.
  Future<QuotaResult> claim();

  /// A scan the app starts on its own (launch, Wi-Fi reconnect). Free, but
  /// on limited plans at most one per [ServerScanQuota.automaticInterval].
  Future<bool> claimAutomatic();
}

/// Claims scans from the server (`claim_scan`, counted per UTC day), and
/// falls back to a local count when the server is unreachable. The local
/// count mirrors the server's last answer, so going offline neither blocks
/// scanning nor resets the allowance.
class ServerScanQuota implements ScanQuota {
  ServerScanQuota(this._store, this._claimOnServer, {DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  /// The Free tier's limit, assumed until the server has answered once.
  static const defaultLimit = 3;
  static const automaticInterval = Duration(minutes: 30);
  static const _timeout = Duration(seconds: 5);

  final LocalStore _store;
  final Future<Map<String, dynamic>> Function() _claimOnServer;
  final DateTime Function() _clock;

  String get _today => _clock().toUtc().toIso8601String().substring(0, 10);

  @override
  Future<QuotaResult> claim() async {
    final day = _today;
    Map<String, dynamic>? answer;
    try {
      answer = await _claimOnServer().timeout(_timeout);
    } catch (_) {
      // Offline, signed out, or the server is down: count locally.
    }
    if (answer != null) {
      final result = QuotaResult(
        allowed: answer['allowed'] == true,
        remaining: (answer['remaining'] as num?)?.toInt(),
        limit: (answer['limit'] as num?)?.toInt(),
      );
      await _remember(day, result);
      return result;
    }
    return _claimLocally(day);
  }

  @override
  Future<bool> claimAutomatic() async {
    if (await _store.setting('quotaLimit') == 'none' ||
        await _store.setting(isPremiumKey) == '1' ||
        await _store.setting(autoScanOnLaunchKey) == '1') {
      return true;
    }
    final now = _clock();
    final last = DateTime.tryParse(await _store.setting('autoScanAt') ?? '');
    if (last != null && now.difference(last) < automaticInterval) return false;
    await _store.setSetting('autoScanAt', now.toUtc().toIso8601String());
    return true;
  }

  Future<void> _remember(String day, QuotaResult r) async {
    await _store.setSetting('quotaLimit', r.limit?.toString() ?? 'none');
    await _store.setSetting(isPremiumKey, r.limit == null ? '1' : '0');
    await _store.setSetting('quotaDay', day);
    if (r.limit != null) await _store.setSetting('quotaUsed', '${r.limit! - (r.remaining ?? 0)}');
  }

  Future<QuotaResult> _claimLocally(String day) async {
    final saved = await _store.setting('quotaLimit');
    if (saved == 'none') return const QuotaResult(allowed: true);
    final limit = int.tryParse(saved ?? '') ?? defaultLimit;
    final used = await _store.setting('quotaDay') == day ? int.tryParse(await _store.setting('quotaUsed') ?? '') ?? 0 : 0;
    if (used >= limit) return QuotaResult(allowed: false, remaining: 0, limit: limit);
    await _store.setSetting('quotaDay', day);
    await _store.setSetting('quotaUsed', '${used + 1}');
    return QuotaResult(allowed: true, remaining: limit - used - 1, limit: limit);
  }
}

/// When the daily allowance comes back: midnight UTC, in local time.
DateTime nextQuotaReset([DateTime? now]) {
  final utc = (now ?? DateTime.now()).toUtc();
  return DateTime.utc(utc.year, utc.month, utc.day + 1).toLocal();
}

/// Setting key for whether this install has a Premium plan.
const isPremiumKey = 'isPremium';

/// Key for automatic scan on app launch setting.
const autoScanOnLaunchKey = 'autoScanOnLaunch';
const defaultAutoScanOnLaunch = true;

/// Whether automatic scan on app launch is enabled in settings.
Future<bool> isAutoScanOnLaunchEnabled(LocalStore store) async {
  final value = await store.setting(autoScanOnLaunchKey);
  if (value == null) return defaultAutoScanOnLaunch;
  return value == '1' || value == 'true';
}

/// Saves the automatic scan on app launch setting.
Future<void> setAutoScanOnLaunch(LocalStore store, bool enabled) async {
  await store.setSetting(autoScanOnLaunchKey, enabled ? '1' : '0');
}

/// Checks whether this install is cached as a Premium user.
Future<bool> isPremiumUser(LocalStore store) async {
  final saved = await store.setting(isPremiumKey);
  if (saved != null) return saved == '1' || saved == 'true';
  final quota = await store.setting('quotaLimit');
  if (quota == 'none') return true;
  final autoScan = await store.setting(autoScanOnLaunchKey);
  return autoScan == '1';
}

/// Saves the Premium entitlement state to local settings.
Future<void> setIsPremiumUser(LocalStore store, bool isPremium) async {
  await store.setSetting(isPremiumKey, isPremium ? '1' : '0');
}

