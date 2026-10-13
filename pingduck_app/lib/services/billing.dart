import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:purchases_flutter/purchases_flutter.dart';

import '../core/constants/revenuecat_config.dart';

/// Store purchases run through Google Play only for now (iOS waits for an
/// iPhone to test on; Windows has no store billing).
bool get billingSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// One way to buy Premium, as the store prices it.
class PlanOffer {
  const PlanOffer({
    required this.id,
    required this.priceString,
    required this.period,
    this.trialDays,
    this.savingsPercent,
    this.raw,
  });

  final String id;

  /// Localized by the store, e.g. "$34.99".
  final String priceString;

  /// "year" or "month".
  final String period;
  final int? trialDays;

  /// For the annual offer: how much cheaper than twelve months.
  final int? savingsPercent;

  /// The SDK's package, handed back to [Billing.buy].
  final Object? raw;
}

/// What the store says about the subscription. For display only: the
/// server's plan (`my_plan()`) decides what is unlocked.
class SubscriptionDetails {
  const SubscriptionDetails({
    required this.active,
    required this.willRenew,
    this.expiresAt,
    this.inTrial = false,
    this.billingIssue = false,
    this.manageUrl,
  });

  final bool active;
  final bool willRenew;
  final DateTime? expiresAt;
  final bool inTrial;
  final bool billingIssue;
  final String? manageUrl;
}

enum PurchaseOutcome { purchased, cancelled, pending }

class BillingException implements Exception {
  const BillingException(this.message);
  final String message;
  @override
  String toString() => message;
}

abstract interface class Billing {
  /// Once at launch. [userId] is the Supabase id of a signed-in (not
  /// anonymous) account, or null.
  Future<void> configure(String? userId);

  /// On sign-in, sign-up or sign-out.
  Future<void> identify(String? userId);

  /// Annual first, then monthly. Empty when billing isn't available.
  Future<List<PlanOffer>> offers();

  Future<PurchaseOutcome> buy(PlanOffer offer);

  Future<void> restore();

  /// Null when billing isn't available or there was never a subscription.
  Future<SubscriptionDetails?> details();
}

class RevenueCatBilling implements Billing {
  bool _configured = false;

  bool get _ready => billingSupported && _configured;

  @override
  Future<void> configure(String? userId) async {
    if (!billingSupported || _configured || !revenueCatKeySet) return;
    await Purchases.configure(PurchasesConfiguration(revenueCatAndroidKey)..appUserID = userId);
    _configured = true;
  }

  @override
  Future<void> identify(String? userId) async {
    if (!_ready) return;
    if (userId != null) {
      await Purchases.logIn(userId);
    } else if (!await Purchases.isAnonymous) {
      // logOut throws when RevenueCat's user is already anonymous.
      await Purchases.logOut();
    }
  }

  @override
  Future<List<PlanOffer>> offers() async {
    if (!_ready) return const [];
    final current = (await Purchases.getOfferings()).current;
    if (current == null) return const [];
    final monthly = current.monthly;
    final annual = current.annual;
    final monthlyPrice = monthly?.storeProduct.price;
    return [
      if (annual != null)
        _offer(
          annual,
          'year',
          savings: monthlyPrice == null || monthlyPrice <= 0
              ? null
              : (100 * (1 - annual.storeProduct.price / (12 * monthlyPrice))).round(),
        ),
      if (monthly != null) _offer(monthly, 'month'),
    ];
  }

  PlanOffer _offer(Package p, String period, {int? savings}) => PlanOffer(
    id: p.identifier,
    priceString: p.storeProduct.priceString,
    period: period,
    trialDays: _trialDays(p.storeProduct.defaultOption?.freePhase?.billingPeriod),
    savingsPercent: savings != null && savings > 0 ? savings : null,
    raw: p,
  );

  static int? _trialDays(Period? period) => switch (period?.unit) {
    PeriodUnit.day => period!.value,
    PeriodUnit.week => period!.value * 7,
    PeriodUnit.month => period!.value * 30,
    PeriodUnit.year => period!.value * 365,
    _ => null,
  };

  @override
  Future<PurchaseOutcome> buy(PlanOffer offer) async {
    if (!_ready || offer.raw is! Package) throw const BillingException('Purchases are not available right now.');
    try {
      await Purchases.purchase(PurchaseParams.package(offer.raw! as Package));
      return PurchaseOutcome.purchased;
    } on PlatformException catch (e) {
      return switch (PurchasesErrorHelper.getErrorCode(e)) {
        PurchasesErrorCode.purchaseCancelledError => PurchaseOutcome.cancelled,
        PurchasesErrorCode.paymentPendingError => PurchaseOutcome.pending,
        PurchasesErrorCode.networkError => throw const BillingException('No connection. Try again when online.'),
        PurchasesErrorCode.productAlreadyPurchasedError =>
          throw const BillingException('This Google account already has Premium. Try Restore purchases.'),
        _ => throw BillingException('Google Play could not complete the purchase (${e.message ?? e.code}).'),
      };
    }
  }

  @override
  Future<void> restore() async {
    if (!_ready) return;
    try {
      await Purchases.restorePurchases();
    } on PlatformException catch (e) {
      throw BillingException('Could not restore purchases (${e.message ?? e.code}).');
    }
  }

  @override
  Future<SubscriptionDetails?> details() async {
    if (!_ready) return null;
    final info = await Purchases.getCustomerInfo();
    final e = info.entitlements.all[premiumEntitlement];
    if (e == null) return null;
    return SubscriptionDetails(
      active: e.isActive,
      willRenew: e.willRenew,
      expiresAt: e.expirationDate == null ? null : DateTime.tryParse(e.expirationDate!)?.toLocal(),
      inTrial: e.periodType == PeriodType.trial,
      billingIssue: e.billingIssueDetectedAt != null,
      manageUrl: info.managementURL ?? playSubscriptionsUrl,
    );
  }
}

final billingProvider = Provider<Billing>((ref) => RevenueCatBilling());
