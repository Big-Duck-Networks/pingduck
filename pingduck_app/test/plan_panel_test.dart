import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/settings/presentation/settings_screen.dart';
import 'package:pingduck_app/features/subscription/presentation/plan_panel.dart';
import 'package:pingduck_app/services/billing.dart';
import 'package:pingduck_app/services/plan.dart';

import 'fakes.dart';

void main() {
  late FakeBilling billing;
  late FakeAuth auth;

  Future<void> pump(
    WidgetTester tester, {
    Plan plan = Plan.free,
    SubscriptionDetails? details,
    bool signedIn = true,
    Widget home = const Scaffold(body: SingleChildScrollView(child: PlanPanel())),
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);
    final store = memoryStore();
    addTearDown(store.close);
    billing = FakeBilling()..subscription = details;
    auth = FakeAuth(accounts: {'me@example.invalid': 'pw'});
    if (signedIn) await tester.runAsync(() => auth.signIn('me@example.invalid', 'pw'));
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        planRepositoryProvider.overrideWithValue(FakePlanRepository([plan])),
        billingProvider.overrideWithValue(billing),
        accountAuthProvider.overrideWithValue(auth),
      ],
      child: MaterialApp(theme: PingDuckTheme.light(), home: home),
    ));
    await tester.pumpAndSettle();
  }

  final soon = DateTime(2026, 11, 3);
  SubscriptionDetails store({bool willRenew = true, bool inTrial = false, bool billingIssue = false}) =>
      SubscriptionDetails(
        active: true,
        willRenew: willRenew,
        expiresAt: soon,
        inTrial: inTrial,
        billingIssue: billingIssue,
        manageUrl: 'https://play.google.com/store/account/subscriptions',
      );

  testWidgets('Free offers Go Premium and Restore', (tester) async {
    await pump(tester);

    expect(find.text('FREE'), findsOneWidget);
    expect(find.textContaining('3 scans a day'), findsOneWidget);
    expect(find.byKey(const Key('go_premium')), findsOneWidget);
    expect(find.byKey(const Key('restore_purchases')), findsOneWidget);
    expect(find.byKey(const Key('manage_subscription')), findsNothing);
  });

  testWidgets('anonymous Free has no Restore; buying signs up first', (tester) async {
    await pump(tester, signedIn: false);

    expect(find.byKey(const Key('go_premium')), findsOneWidget);
    expect(find.byKey(const Key('restore_purchases')), findsNothing);
  });

  testWidgets('a renewing subscription shows its renewal date and Manage', (tester) async {
    await pump(tester, plan: Plan.premium, details: store());

    expect(find.text('PREMIUM'), findsOneWidget);
    expect(find.textContaining('Renews '), findsOneWidget);
    expect(find.byKey(const Key('manage_subscription')), findsOneWidget);
    expect(find.byKey(const Key('go_premium')), findsNothing);
  });

  testWidgets('a trial says when it ends', (tester) async {
    await pump(tester, plan: Plan.premium, details: store(inTrial: true));
    expect(find.textContaining('Free trial · Ends '), findsOneWidget);
  });

  testWidgets('a cancelled subscription says Premium lasts until the period ends', (tester) async {
    await pump(tester, plan: Plan.premium, details: store(willRenew: false));
    expect(find.textContaining('Cancelled · Premium until '), findsOneWidget);
  });

  testWidgets('a payment problem points to Google Play', (tester) async {
    await pump(tester, plan: Plan.premium, details: store(billingIssue: true));
    expect(find.textContaining('Payment problem'), findsOneWidget);
  });

  testWidgets('Premium without a store subscription has no Manage button', (tester) async {
    await pump(tester, plan: Plan.premium);

    expect(find.text('Premium is active on this account.'), findsOneWidget);
    expect(find.byKey(const Key('manage_subscription')), findsNothing);
  });

  testWidgets('deleting the account warns while a subscription renews', (tester) async {
    await pump(tester, plan: Plan.premium, details: store(), home: const SettingsScreen(initialIndex: 1));
    await tester.ensureVisible(find.text('DELETE ACCOUNT'));
    await tester.tap(find.text('DELETE ACCOUNT'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete_subscription_warning')), findsOneWidget);
    expect(find.text('OPEN GOOGLE PLAY'), findsOneWidget);

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();
    expect(auth.deletions, 0);
  });

  testWidgets('deleting the account without a renewing subscription has no warning', (tester) async {
    await pump(tester, plan: Plan.premium, details: store(willRenew: false), home: const SettingsScreen(initialIndex: 1));
    await tester.ensureVisible(find.text('DELETE ACCOUNT'));
    await tester.tap(find.text('DELETE ACCOUNT'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('delete_subscription_warning')), findsNothing);
    expect(find.text('DELETE'), findsOneWidget);
  });
}
