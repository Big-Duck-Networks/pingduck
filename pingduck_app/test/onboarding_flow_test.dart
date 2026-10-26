import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/onboarding/onboarding_screen.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';

import 'fakes.dart';

void main() {
  testWidgets('Onboarding 3-step sequence walks through privacy, location, and account', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    addTearDown(tester.view.reset);

    var doneCalled = false;
    final store = memoryStore();
    addTearDown(store.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.dark(),
          home: OnboardingScreen(onDone: () => doneCalled = true),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // -------------------------------------------------------------
    // Step 1: Privacy Defaults
    // -------------------------------------------------------------
    expect(find.text('Your network, your rules'), findsOneWidget);
    expect(
      find.text(
        "We've set privacy defaults that protect you from the start. Review your preferences anytime in the App settings.",
      ),
      findsOneWidget,
    );
    expect(find.text('Agree and continue'), findsOneWidget);
    expect(find.text('Review settings and policies'), findsOneWidget);

    // Open privacy settings screen
    await tester.tap(find.text('Review settings and policies'));
    await tester.pumpAndSettle();
    expect(find.text('Privacy settings'), findsOneWidget);
    expect(find.text('Analytics Settings'), findsOneWidget);
    expect(find.text('Crash reporting'), findsOneWidget);
    expect(find.text('Send reports to developers when the App crashes.'), findsOneWidget);
    expect(find.byKey(const Key('crash_reporting_switch')), findsOneWidget);
    expect(find.text('Privacy policy'), findsWidgets);
    expect(find.text('Terms of service'), findsOneWidget);

    // Toggle crash reporting switch
    await tester.tap(find.byKey(const Key('crash_reporting_switch')));
    await tester.pumpAndSettle();

    // Pop back to Step 1
    final settingsBackFinder = find.descendant(
      of: find.byType(AppBar),
      matching: find.byType(IconButton),
    );
    await tester.tap(settingsBackFinder);
    await tester.pumpAndSettle();

    // Advance to Step 2
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();

    // -------------------------------------------------------------
    // Step 2: Location Access
    // -------------------------------------------------------------
    expect(find.text('Enable location to detect your Wi-Fi'), findsOneWidget);
    expect(
      find.text(
        'PingDuck uses location access to identify your exact network and keep your device names consistent across scans.',
      ),
      findsOneWidget,
    );
    expect(find.text('Continue'), findsOneWidget);
    expect(find.text('Use without Wi-Fi details'), findsOneWidget);

    // Verify back button works to return to Step 1
    final backFinder = find.byTooltip('Back');
    expect(backFinder, findsOneWidget);
    await tester.tap(backFinder);
    await tester.pumpAndSettle();
    expect(find.text('Your network, your rules'), findsOneWidget);

    // Return to Step 2 and advance
    await tester.tap(find.text('Agree and continue'));
    await tester.pumpAndSettle();
    expect(find.text('Enable location to detect your Wi-Fi'), findsOneWidget);

    await tester.tap(find.text('Use without Wi-Fi details'));
    await tester.pumpAndSettle();

    // -------------------------------------------------------------
    // Step 3: Account Creation & Smart Scans
    // -------------------------------------------------------------
    expect(find.text('Join PingDuck for more smart scans'), findsOneWidget);
    expect(
      find.text(
        'Create your free account to get network alerts, extra scans today, outage updates, and priority support.',
      ),
      findsOneWidget,
    );
    expect(find.text('Sign in with Google'), findsOneWidget);
    expect(find.text('Or continue with email'), findsOneWidget);
    expect(find.text("I'll think about it"), findsOneWidget);

    // Skip account creation to complete onboarding
    expect(doneCalled, isFalse);
    await tester.tap(find.text("I'll think about it"));
    await tester.pumpAndSettle();
    expect(doneCalled, isTrue);
  });
}
