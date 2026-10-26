import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_colors.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/core/theme/theme_mode_provider.dart';
import 'package:pingduck_app/features/agent/application/agent_status.dart';
import 'package:pingduck_app/features/agent/domain/agent_unit.dart';
import 'package:pingduck_app/features/auth/account_auth.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/features/settings/presentation/settings_screen.dart';
import 'package:pingduck_app/features/shell/app_shell.dart';
import 'package:pingduck_app/services/push_alerts.dart';
import 'package:pingduck_app/services/supabase_sync.dart';

import 'fakes.dart';

void main() {
  test('PingDuckTheme.dark builds pitch-black AMOLED dark theme', () {
    final dark = PingDuckTheme.dark();
    expect(dark.brightness, Brightness.dark);
    expect(dark.scaffoldBackgroundColor, PingDuckColors.darkCanvas);
    expect(dark.colorScheme.surface, PingDuckColors.darkCanvas);
    expect(dark.colorScheme.onSurface, PingDuckColors.darkInk);
  });

  test('PingDuckColors palette toggles between light and dark', () {
    PingDuckColors.isDark = false;
    expect(PingDuckColors.canvas, PingDuckColors.lightCanvas);
    expect(PingDuckColors.ink, PingDuckColors.lightInk);

    PingDuckColors.isDark = true;
    expect(PingDuckColors.canvas, PingDuckColors.darkCanvas);
    expect(PingDuckColors.surface1, PingDuckColors.darkSurface1);
    expect(PingDuckColors.ink, PingDuckColors.darkInk);
    PingDuckColors.isDark = false; // Reset
  });

  testWidgets('App settings shows Theme row and switches theme', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);
    final repo = FakeSyncRepository();
    final alerts = FakePushAlerts();
    final auth = FakeAuth(accounts: {'me@example.invalid': 'pw'});

    await store.setSetting(appThemeModeKey, 'system');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
          accountAuthProvider.overrideWithValue(auth),
          myAgentsProvider.overrideWith((ref) async => const <PairedAgent>[]),
          isPremiumProvider.overrideWith((ref) async => false),
          syncRepositoryProvider.overrideWithValue(repo),
          pushAlertsProvider.overrideWithValue(alerts),
          supabaseSyncProvider.overrideWith(() => SupabaseSync(debounce: Duration.zero)),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          darkTheme: PingDuckTheme.dark(),
          home: const SettingsScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('APPEARANCE'), findsOneWidget);
    expect(find.text('Theme'), findsOneWidget);
    expect(find.text('System default'), findsOneWidget);

    // Tap theme row to open sheet
    await tester.tap(find.text('Theme'));
    await tester.pumpAndSettle();

    expect(find.text('THEME'), findsOneWidget);
    expect(find.text('Dark (pitch-black AMOLED)'), findsOneWidget);

    // Select Dark
    await tester.tap(find.text('Dark (pitch-black AMOLED)'));
    await tester.pumpAndSettle();

    expect(await store.setting(appThemeModeKey), 'dark');
    expect(find.text('Dark (pitch-black AMOLED)'), findsOneWidget);
  });

  testWidgets('Dark themeMode activates PingDuckColors.isDark in AppShell', (tester) async {
    final store = memoryStore();
    addTearDown(store.close);
    await store.setSetting(appThemeModeKey, 'dark');

    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          localStoreProvider.overrideWithValue(store),
        ],
        child: MaterialApp(
          theme: PingDuckTheme.light(),
          darkTheme: PingDuckTheme.dark(),
          themeMode: ThemeMode.dark,
          home: const AppShell(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(PingDuckColors.isDark, isTrue);
    expect(PingDuckColors.canvas, const Color(0xFF000000));
    expect(PingDuckColors.surface1, const Color(0xFF121214));
    expect(PingDuckColors.ink, const Color(0xFFFFFFFF));
    PingDuckColors.isDark = false;
  });
}
