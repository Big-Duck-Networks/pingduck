import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'core/constants/supabase_config.dart';
import 'core/desktop/desktop.dart';
import 'core/network/lan_connectivity.dart';
import 'core/theme/pingduck_colors.dart';
import 'core/theme/pingduck_theme.dart';
import 'core/theme/theme_mode_provider.dart';
import 'features/agent/application/agent_status.dart';
import 'features/auth/account_auth.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/scanner/application/scan_controller.dart';
import 'features/settings/presentation/settings_screen.dart';
import 'features/shell/app_shell.dart';
import 'services/billing.dart';
import 'services/local_storage.dart';
import 'services/plan.dart';
import 'services/push_alerts.dart';
import 'services/scan_quota.dart';
import 'services/supabase_sync.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();
  await initDesktop(args);

  // Cached devices load before the first frame so the radar is never empty
  // on launch; the scan then lights them up.
  final store = LocalStore();
  final restored = await restoreLastScan(store);
  final onboarded = await store.setting('onboarded') == '1';

  // Reads the saved session from disk only; nothing here waits on the network,
  // so launch stays instant offline.
  await Supabase.initialize(url: supabaseUrl, publishableKey: supabasePublishableKey);
  await initPushAlerts();

  runApp(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      restoredScanProvider.overrideWithValue(restored),
      onboardedProvider.overrideWith(() => Onboarded(onboarded)),
    ],
    child: const DesktopShell(child: PingDuckApp()),
  ));
}

void _registerFontLicenses() {
  LicenseRegistry.addLicense(() async* {
    for (final (pkg, file) in [('Space Grotesk', 'OFL-SpaceGrotesk.txt'), ('Inter', 'OFL-Inter.txt')]) {
      yield LicenseEntryWithLineBreaks([pkg], await rootBundle.loadString('assets/fonts/$file'));
    }
  });
}

final onboardedProvider = NotifierProvider<Onboarded, bool>(() => Onboarded(true));

class Onboarded extends Notifier<bool> {
  Onboarded(this.initial);
  final bool initial;

  @override
  bool build() => initial;

  Future<void> complete() async {
    state = true;
    await ref.read(localStoreProvider).setSetting('onboarded', '1');
  }
}

class PingDuckApp extends ConsumerStatefulWidget {
  const PingDuckApp({super.key});

  @override
  ConsumerState<PingDuckApp> createState() => _PingDuckAppState();
}

class _PingDuckAppState extends ConsumerState<PingDuckApp> with WidgetsBindingObserver {
  void _startSync() => ref.read(supabaseSyncProvider.notifier).start();

  // Realtime sockets don't survive the background; reconnect on return.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startSync();
      ref.read(currentPlanProvider.notifier).refresh();
    }
  }

  // Store purchases belong to an account, never to the anonymous user, so
  // RevenueCat only knows the Supabase id once an email account is signed in.
  // Billing never blocks or breaks launch.
  void _startBilling() {
    final auth = ref.read(accountAuthProvider);
    final billing = ref.read(billingProvider);
    billing.configure(auth.accountId).catchError((Object e) => debugPrint('billing: $e'));
    ref.listenManual(accountEmailProvider, (prev, next) {
      if (prev?.value == next.value) return;
      billing.identify(auth.accountId).catchError((Object e) => debugPrint('billing: $e'));
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startBilling();
    // Cloud sync never blocks launch; it starts after the first frame.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startSync());
    ref.read(pushAlertsProvider).listen(() => ref.read(supabaseSyncProvider.notifier).refresh());
    // Returning users get a fresh scan on launch unless they turned it off in
    // Settings; the server limits how often Free ones run. New users start it
    // from onboarding.
    // Offline, there is nothing to scan; the shell starts one when Wi-Fi returns.
    if (ref.read(onboardedProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final store = ref.read(localStoreProvider);
        final autoScanEnabled = await isAutoScanOnLaunchEnabled(store);
        if (!autoScanEnabled) return;
        if (await store.setting(autoScanOnLaunchKey) == null) {
          await setAutoScanOnLaunch(store, true);
        }
        final connected = ref.read(lanConnectedProvider).isOnLan ||
            await ref.read(lanConnectedProvider.future).catchError((_) => true);
        if (connected) {
          ref.read(scanControllerProvider.notifier).scan(automatic: true);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Pairing or revoking an agent changes what there is to sync.
    ref.listen(myAgentsProvider, (prev, next) {
      if (next.hasValue && prev?.value?.length != next.value?.length) _startSync();
    });
    final onboarded = ref.watch(onboardedProvider);
    final themeMode = ref.watch(appThemeModeProvider);
    final platformBrightness = View.of(context).platformDispatcher.platformBrightness;
    final isDark = switch (themeMode) {
      ThemeMode.dark => true,
      ThemeMode.light => false,
      ThemeMode.system => platformBrightness == Brightness.dark,
    };
    PingDuckColors.isDark = isDark;

    return MaterialApp(
      title: 'PingDuck',
      debugShowCheckedModeBanner: false,
      theme: PingDuckTheme.light(),
      darkTheme: PingDuckTheme.dark(),
      themeMode: themeMode,
      builder: (context, child) {
        final platformBrightness = MediaQuery.platformBrightnessOf(context);
        final isDark = switch (themeMode) {
          ThemeMode.dark => true,
          ThemeMode.light => false,
          ThemeMode.system => platformBrightness == Brightness.dark,
        };
        PingDuckColors.isDark = isDark;
        return child ?? const SizedBox.shrink();
      },
      home: onboarded
          ? const AppShell()
          : OnboardingScreen(onDone: () async {
              await ref.read(onboardedProvider.notifier).complete();
              ref.read(scanControllerProvider.notifier).scan(automatic: true);
            }),
    );
  }
}
