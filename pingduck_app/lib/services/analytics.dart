import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:posthog_flutter/posthog_flutter.dart';

import '../core/constants/posthog_config.dart';
import 'local_storage.dart';

/// Local setting key storing `'1'` (enabled, default) or `'0'` (opted out).
const crashReportingKey = 'crashReporting';

/// Reads the user's saved opt-out choice (defaults to enabled / true).
Future<bool> isCrashReportingEnabled(LocalStore store) async {
  final val = await store.setting(crashReportingKey);
  return val != '0';
}

/// Saves the user's choice and immediately updates the analytics / crash
/// reporting SDK at runtime.
Future<void> setCrashReportingEnabled(
  LocalStore store,
  Analytics analytics,
  bool enabled,
) async {
  await store.setSetting(crashReportingKey, enabled ? '1' : '0');
  await analytics.setEnabled(enabled);
}

/// Property keys that must never leave the device in analytics events.
const disallowedAnalyticsKeys = {
  'ip',
  'mac',
  'hostname',
  'ssid',
  'bssid',
  'gateway',
  'cidr',
  'devices',
  'email',
};

/// Scrubs any network/PII keys from an event property map as a defense-in-depth
/// guard.
Map<String, Object>? sanitizeAnalyticsProperties(Map<String, Object>? properties) {
  if (properties == null || properties.isEmpty) return null;
  final cleaned = <String, Object>{
    for (final entry in properties.entries)
      if (!disallowedAnalyticsKeys.contains(entry.key.toLowerCase())) entry.key: entry.value,
  };
  return cleaned.isEmpty ? null : cleaned;
}

/// Crash reporting and anonymous product analytics, wired to the Privacy
/// Settings opt-out switch.
///
/// Only high-level product events (`scan started`, `scan finished`,
/// `user signed up`, `paywall viewed`) and unhandled exceptions are captured —
/// never IPs, MACs, hostnames, SSIDs, or device lists.
abstract interface class Analytics {
  /// Initializes the SDK once at launch with the user's current opt-in state.
  Future<void> configure({required bool enabled});

  /// Opts in or out at runtime when the user toggles the Privacy Settings switch.
  Future<void> setEnabled(bool enabled);

  /// Records a product event when enabled.
  Future<void> capture(String event, [Map<String, Object>? properties]);

  /// Records an unhandled or notable exception when enabled.
  Future<void> captureException(Object error, {StackTrace? stackTrace});
}

class PostHogAnalytics implements Analytics {
  bool _configured = false;
  bool _enabled = true;

  @override
  Future<void> configure({required bool enabled}) async {
    _enabled = enabled;
    if (_configured || !posthogKeySet) return;
    final config = PostHogConfig(
      posthogProjectToken,
      beforeSend: [
        (event) {
          final props = event.properties;
          if (props != null) {
            props.removeWhere((k, _) => disallowedAnalyticsKeys.contains(k.toLowerCase()));
          }
          return event;
        },
      ],
    )
      ..host = posthogHost
      ..optOut = !enabled
      ..personProfiles = PostHogPersonProfiles.never
      ..preloadFeatureFlags = false
      ..sendFeatureFlagEvent = false
      ..surveys = false
      ..sessionReplay = false
      ..capturePushNotificationSubscriptions = false
      ..capturePushNotificationOpened = false
      ..captureApplicationLifecycleEvents = true
      ..errorTrackingConfig.captureFlutterErrors = true
      ..errorTrackingConfig.capturePlatformDispatcherErrors = true
      ..errorTrackingConfig.captureIsolateErrors = true
      ..errorTrackingConfig.captureNativeExceptions = true
      ..errorTrackingConfig.captureNativeCrashes = true
      ..errorTrackingConfig.inAppIncludes.addAll(['pingduck_app', 'pingduck_core']);

    try {
      await Posthog().setup(config);
      _configured = true;
    } catch (e) {
      debugPrint('analytics setup: $e');
    }
  }

  @override
  Future<void> setEnabled(bool enabled) async {
    _enabled = enabled;
    if (!posthogKeySet) return;
    if (!_configured) {
      if (enabled) await configure(enabled: true);
      return;
    }
    try {
      await (enabled ? Posthog().optIn() : Posthog().optOut());
    } catch (e) {
      debugPrint('analytics opt-in/out: $e');
    }
  }

  @override
  Future<void> capture(String event, [Map<String, Object>? properties]) async {
    if (!_enabled || !_configured || !posthogKeySet) return;
    try {
      await Posthog().capture(
        eventName: event,
        properties: sanitizeAnalyticsProperties(properties),
      );
    } catch (e) {
      debugPrint('analytics capture: $e');
    }
  }

  @override
  Future<void> captureException(Object error, {StackTrace? stackTrace}) async {
    if (!_enabled || !_configured || !posthogKeySet) return;
    try {
      await Posthog().captureException(error: error, stackTrace: stackTrace);
    } catch (e) {
      debugPrint('analytics exception: $e');
    }
  }
}

final analyticsProvider = Provider<Analytics>((ref) => PostHogAnalytics());

