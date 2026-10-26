import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/account/presentation/account_storage_screen.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/services/billing.dart';
import 'package:pingduck_app/services/plan.dart';

import 'fakes.dart';

void main() {
  testWidgets('AccountStorageScreen renders all storage status rows and buttons', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const AccountStorageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Account storage'), findsOneWidget);
    expect(find.text('Account'), findsOneWidget);
    expect(find.text('FREE'), findsOneWidget);
    expect(find.text('Account state'), findsOneWidget);
    expect(find.text('LOCAL'), findsOneWidget);
    expect(find.text('Networks in your account'), findsOneWidget);
    expect(find.byKey(const Key('restore_storage_button')), findsOneWidget);
    expect(find.byKey(const Key('refresh_storage_button')), findsOneWidget);
    expect(find.text('LOCAL CACHE'), findsOneWidget);
    expect(find.text('Local inventory'), findsOneWidget);
    expect(find.text('CLEAR DEVICE INVENTORY'), findsOneWidget);
  });

  testWidgets('AccountStorageScreen shows OK and PRO when signed in with paid plan', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);
    final auth = FakeAuth(accounts: {'me@example.invalid': 'pw'});
    await tester.runAsync(() => auth.signIn('me@example.invalid', 'pw'));

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          accountAuthProvider.overrideWithValue(auth),
          planRepositoryProvider.overrideWithValue(FakePlanRepository([Plan.premium])),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const AccountStorageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('PRO'), findsOneWidget);
    expect(find.text('OK'), findsOneWidget);
  });

  testWidgets('Clear device inventory opens dialog and cancel leaves it intact', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const AccountStorageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('CLEAR DEVICE INVENTORY'));
    await tester.pumpAndSettle();

    expect(find.text('CLEAR INVENTORY?'), findsOneWidget);
    expect(find.text('CANCEL'), findsOneWidget);
    expect(find.text('CLEAR'), findsOneWidget);

    await tester.tap(find.text('CANCEL'));
    await tester.pumpAndSettle();

    expect(find.text('CLEAR INVENTORY?'), findsNothing);
  });

  testWidgets('Restore button triggers restore and shows snackbar', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);
    final billing = FakeBilling();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          billingProvider.overrideWithValue(billing),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          home: const AccountStorageScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('restore_storage_button')));
    await tester.pumpAndSettle();

    expect(find.text('Account storage up to date.'), findsOneWidget);
  });
}
