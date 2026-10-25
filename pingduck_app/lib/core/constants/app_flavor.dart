import 'package:flutter/services.dart';

/// Application flavors for PingDuck.
enum AppFlavor {
  dev,
  prod;

  /// Returns the current active runtime flavor based on Flutter's [appFlavor].
  static AppFlavor get current {
    switch (appFlavor) {
      case 'dev':
        return AppFlavor.dev;
      case 'prod':
      default:
        return AppFlavor.prod;
    }
  }

  /// True when running in the development flavor.
  bool get isDev => this == AppFlavor.dev;

  /// True when running in the production flavor.
  bool get isProd => this == AppFlavor.prod;

  /// Human-readable name for logging or display.
  String get label => this == AppFlavor.dev ? 'dev' : 'prod';
}
