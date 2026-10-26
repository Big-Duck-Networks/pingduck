import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../features/scanner/application/scan_controller.dart';

const appThemeModeKey = 'appThemeMode';

class AppThemeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() {
    _load();
    return ThemeMode.system;
  }

  Future<void> _load() async {
    final val = await ref.read(localStoreProvider).setting(appThemeModeKey);
    state = switch (val) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final val = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await ref.read(localStoreProvider).setSetting(appThemeModeKey, val);
  }
}

/// App theme mode provider. Defaults to [ThemeMode.system].
final appThemeModeProvider = NotifierProvider<AppThemeNotifier, ThemeMode>(AppThemeNotifier.new);

/// Persists user chosen theme mode.
Future<void> setAppThemeMode(WidgetRef ref, ThemeMode mode) async {
  await ref.read(appThemeModeProvider.notifier).setMode(mode);
}
