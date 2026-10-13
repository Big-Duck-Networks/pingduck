import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/subscription/presentation/paywall_screen.dart';
import 'package:pingduck_app/services/billing.dart';
import 'package:pingduck_app/services/plan.dart';

import 'fakes.dart';

/// Buying flips the server's answer, as the webhook would.
class _Billing extends FakeBilling {
  VoidCallback? onBuy;

  @override
  Future<PurchaseOutcome> buy(PlanOffer offer) async {
    final outcome = await super.buy(offer);
    if (outcome == PurchaseOutcome.purchased) onBuy?.call();
    return outcome;
  }
}

void main() {
  late FakePlanRepository repo;
  late _Billing billing;
  late FakeAuth auth;
  bool? result;

  Future<void> pump(WidgetTester tester, {bool signedIn = true, Plan plan = Plan.free}) async {
    tester.view.physicalSize = const Size(1080, 3600);
    addTearDown(tester.view.reset);
    final store = memoryStore();
    addTearDown(store.close);
    repo = FakePlanRepository([plan]);
    billing = _Billing()..onBuy = () => repo.plans[0] = Plan.premium;
    auth = FakeAuth(accounts: {'me@example.invalid': 'pw'});
    result = null;
    if (signedIn) await tester.runAsync(() => auth.signIn('me@example.invalid', 'pw'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        planRepositoryProvider.overrideWithValue(repo),
        billingProvider.overrideWithValue(billing),
        accountAuthProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(
        theme: PingDuckTheme.light(),
        home: Consumer(
          builder: (context, ref, _) {
            ref.watch(currentPlanProvider);
            return Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () async => result = await openPaywall(context, ref),
                  child: const Text('OPEN'),
                ),
              ),
            );
          },
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  Future<void> open(WidgetTester tester) async {
    await tester.tap(find.text('OPEN'));
    await tester.pumpAndSettle();
  }

  Future<void> buy(WidgetTester tester) async {
    await tester.tap(find.byKey(const Key('paywall_buy')));
    await tester.pumpAndSettle();
  }

  testWidgets('an anonymous user is asked to create an account first', (tester) async {
    await pump(tester, signedIn: false);
    await open(tester);

    expect(find.textContaining('Create an account first'), findsOneWidget);
    expect(find.text('At least 8 characters'), findsOneWidget);
    expect(find.text('PingDuck Premium'), findsNothing);

    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(result, isFalse);
    expect(billing.calls, isEmpty);
  });

  testWidgets('offers show yearly first with its savings and the trial terms', (tester) async {
    await pump(tester);
    await open(tester);

    expect(find.text('PingDuck Premium'), findsOneWidget);
    expect(tester.getTopLeft(find.text('Yearly')).dy, lessThan(tester.getTopLeft(find.text('Monthly')).dy));
    expect(find.text('SAVE 42%'), findsOneWidget);
    expect(find.text('START 7-DAY FREE TRIAL'), findsOneWidget);
    expect(find.textContaining(r'7 days free, then $34.99 per year.'), findsOneWidget);

    await tester.tap(find.byKey(const Key('offer_month')));
    await tester.pumpAndSettle();
    expect(find.textContaining(r'7 days free, then $4.99 per month.'), findsOneWidget);
  });

  testWidgets('a purchase waits for the server, then Premium is active', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.byKey(const Key('offer_month')));
    await tester.pumpAndSettle();
    await buy(tester);

    expect(billing.calls, ['identify:user-me@example.invalid', r'buy:$rc_monthly']);
    expect(find.text('Premium is active'), findsOneWidget);
    expect(find.text('PingDuck Premium'), findsNothing);
    expect(result, isTrue);
  });

  testWidgets('a cancelled purchase stays on the paywall', (tester) async {
    await pump(tester);
    billing.outcome = PurchaseOutcome.cancelled;
    await open(tester);
    await buy(tester);

    expect(find.text('PingDuck Premium'), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
    expect(result, isNull);
  });

  testWidgets('a store error is shown and the paywall stays', (tester) async {
    await pump(tester);
    billing.buyError = const BillingException('No connection. Try again when online.');
    await open(tester);
    await buy(tester);

    expect(find.text('No connection. Try again when online.'), findsOneWidget);
    expect(find.text('PingDuck Premium'), findsOneWidget);
  });

  testWidgets('restore with nothing to restore says so', (tester) async {
    await pump(tester);
    await open(tester);
    await tester.tap(find.text('RESTORE PURCHASES'));
    await tester.pump(const Duration(seconds: 20));
    await tester.pumpAndSettle();

    expect(billing.calls, contains('restore'));
    expect(find.text('No active subscription found for this Google account.'), findsOneWidget);
    expect(find.text('PingDuck Premium'), findsOneWidget);
  });

  testWidgets('no offers shows that Premium is unavailable, with Retry', (tester) async {
    await pump(tester);
    billing.offerList = const [];
    await open(tester);

    expect(find.textContaining('isn’t available to buy right now'), findsOneWidget);
    expect(find.text('RETRY'), findsOneWidget);
    expect(find.byKey(const Key('paywall_buy')), findsNothing);

    // Prices arrive on a retry.
    billing.offerList = FakeBilling().offerList;
    await tester.tap(find.text('RETRY'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('paywall_buy')), findsOneWidget);
  });

  testWidgets('an account that already has Premium skips the paywall', (tester) async {
    await pump(tester, plan: Plan.premium);
    await open(tester);

    expect(find.text('Premium is already active on this account.'), findsOneWidget);
    expect(find.text('PingDuck Premium'), findsNothing);
    expect(result, isTrue);
  });
}
