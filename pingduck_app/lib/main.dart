import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/network/lan_connectivity.dart';
import 'core/theme/pingduck_theme.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/scanner/application/scan_controller.dart';
import 'features/shell/app_shell.dart';
import 'services/local_storage.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerFontLicenses();

  // Cached devices load before the first frame so the radar is never empty
  // on launch; the scan then lights them up.
  final store = LocalStore();
  final restored = await restoreLastScan(store);
  final onboarded = await store.setting('onboarded') == '1';

  runApp(ProviderScope(
    overrides: [
      localStoreProvider.overrideWithValue(store),
      restoredScanProvider.overrideWithValue(restored),
      onboardedProvider.overrideWith(() => Onboarded(onboarded)),
    ],
    child: const PingDuckApp(),
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

class _PingDuckAppState extends ConsumerState<PingDuckApp> {
  @override
  void initState() {
    super.initState();
    // Returning users get a fresh scan on launch; new users start it from
    // onboarding.
    // Offline, there is nothing to scan; the shell starts one when Wi-Fi returns.
    if (ref.read(onboardedProvider)) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (await ref.read(lanConnectedProvider.future)) ref.read(scanControllerProvider.notifier).scan();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final onboarded = ref.watch(onboardedProvider);
    return MaterialApp(
      title: 'PingDuck',
      debugShowCheckedModeBanner: false,
      theme: PingDuckTheme.light(),
      home: onboarded
          ? const AppShell()
          : OnboardingScreen(onDone: () async {
              await ref.read(onboardedProvider.notifier).complete();
              ref.read(scanControllerProvider.notifier).scan();
            }),
    );
  }
}
