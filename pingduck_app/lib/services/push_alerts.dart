import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/supabase_config.dart';
import '../features/recognition/vendor_name.dart';
import '../features/scanner/application/scan_controller.dart';
import '../firebase_options.dart';
import 'local_storage.dart';

/// New-device alerts (Android). The server sends a data-only FCM message
/// carrying just the network id (supabase/functions/notify-new-devices); the
/// app reads the details with the user's own session and shows the
/// notification itself, so no device data passes through Google.

/// Local setting; '1' when this phone is registered for alerts.
const alertsEnabledKey = 'alerts_enabled';

const _channel = AndroidNotificationChannel(
  'new_devices',
  'New devices',
  description: 'A device joined a network your monitoring unit watches.',
  importance: Importance.high,
);

/// Where the main isolate listens for alerts that arrive in the background.
const _portName = 'pingduck_alerts';

/// supabase_flutter's own key for the saved session (see Supabase.initialize).
final _sessionKey = 'sb-${Uri.parse(supabaseUrl).host.split('.').first}-auth-token';

bool get alertsSupported => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

class NotificationsDeniedException implements Exception {
  const NotificationsDeniedException();
}

/// One device in an alert, as `device_events` embeds it.
class AlertDevice {
  const AlertDevice({this.hostname, this.vendor, this.mac});
  final String? hostname;
  final String? vendor;
  final String? mac;

  String get displayName =>
      [hostname, VendorName.of(vendor), mac].firstWhere((s) => s != null && s.isNotEmpty, orElse: () => null) ??
      'Unknown device';
}

/// The notification's title and body: up to three names, then "and N more".
({String title, String body}) newDeviceAlertText(List<AlertDevice> devices, String? networkName) {
  final where = (networkName == null || networkName.isEmpty) ? 'your network' : networkName;
  if (devices.isEmpty) return (title: 'New device on $where', body: 'Open PingDuck to see it.');
  final title = devices.length == 1 ? 'New device on $where' : '${devices.length} new devices on $where';
  final names = devices.take(3).map((d) => d.displayName).join(', ');
  final more = devices.length - 3;
  return (title: title, body: more > 0 ? '$names and $more more' : names);
}

/// Called once in main(), before runApp. Reads nothing from the network.
Future<void> initPushAlerts() async {
  if (!alertsSupported) return;
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  FirebaseMessaging.onBackgroundMessage(onBackgroundAlert);
}

/// Runs in a separate isolate when a message arrives with the app in the
/// background or closed.
///
/// If the app's main isolate is alive it handles the alert, because it owns
/// the session: refreshing the token here would rotate the refresh token
/// under it, and Supabase's reuse detection could then sign the user out.
/// Only when no main isolate answers does this isolate restore the saved
/// session itself, and it saves any refreshed token back for the next launch.
@pragma('vm:entry-point')
Future<void> onBackgroundAlert(RemoteMessage message) async {
  final networkId = _networkOf(message);
  if (networkId == null) return;
  if (await _handOff(networkId)) return;

  WidgetsFlutterBinding.ensureInitialized();
  final storage = SharedPreferencesLocalStorage(persistSessionKey: _sessionKey);
  await storage.initialize();
  final saved = await storage.accessToken();
  if (saved == null) return; // signed out: nothing to show
  final client = SupabaseClient(supabaseUrl, supabasePublishableKey);
  try {
    final before = client.auth.currentSession;
    await client.auth.recoverSession(saved);
    final after = client.auth.currentSession;
    if (after == null) return;
    if (after.refreshToken != before?.refreshToken) {
      await storage.persistSession(jsonEncode(after.toJson()));
    }
    await showNewDeviceAlert(client, networkId);
  } catch (e) {
    debugPrint('new-device alert: $e');
  } finally {
    await client.dispose();
  }
}

String? _networkOf(RemoteMessage m) =>
    m.data['kind'] == 'new_devices' ? m.data['network_id'] as String? : null;

/// Sends the alert to the main isolate and waits briefly for it to confirm.
Future<bool> _handOff(String networkId) async {
  final main = IsolateNameServer.lookupPortByName(_portName);
  if (main == null) return false;
  final reply = ReceivePort();
  try {
    main.send([networkId, reply.sendPort]);
    return await reply.first.timeout(const Duration(seconds: 3), onTimeout: () => false) == true;
  } finally {
    reply.close();
  }
}

final _notifications = FlutterLocalNotificationsPlugin();
var _notificationsReady = false;

Future<void> _ensureNotifications() async {
  if (_notificationsReady) return;
  await _notifications.initialize(
    settings: const InitializationSettings(android: AndroidInitializationSettings('ic_launcher_monochrome')),
  );
  await _notifications
      .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
      ?.createNotificationChannel(_channel);
  _notificationsReady = true;
}

/// Reads the network's new devices from the last 15 minutes and shows one
/// notification for the network; a later alert replaces it.
Future<void> showNewDeviceAlert(SupabaseClient client, String networkId) async {
  final since = DateTime.now().toUtc().subtract(const Duration(minutes: 15)).toIso8601String();
  final events = await client
      .from('device_events')
      .select('devices(hostname, vendor, mac, is_known)')
      .eq('network_id', networkId)
      .eq('kind', 'new_device')
      .gte('created_at', since)
      .order('created_at', ascending: false)
      .limit(50);
  final network = await client.from('networks').select('name, ssid').eq('id', networkId).maybeSingle();
  // Not this account's network (someone else signed in on this phone since).
  if (network == null) return;

  final devices = [
    for (final e in events)
      if (e['devices'] case {'is_known': false} && final d)
        AlertDevice(hostname: d['hostname'] as String?, vendor: d['vendor'] as String?, mac: d['mac'] as String?),
  ];
  final text = newDeviceAlertText(devices, (network['ssid'] ?? network['name']) as String?);
  await _ensureNotifications();
  await _notifications.show(
    id: networkId.hashCode,
    title: text.title,
    body: text.body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _channel.id,
        _channel.name,
        channelDescription: _channel.description,
        importance: Importance.high,
        priority: Priority.high,
        icon: 'ic_launcher_monochrome',
      ),
    ),
  );
}

/// Registering this phone for alerts and handling the ones that arrive
/// while the app runs.
abstract interface class PushAlerts {
  Future<bool> isEnabled();

  /// Asks for notification permission and registers this phone's token.
  /// Throws [NotificationsDeniedException] when the user says no.
  Future<void> enable();

  Future<void> disable();

  /// Starts handling alerts in the app's main isolate; [onAlert] runs after
  /// each one is shown (e.g. to re-sync).
  void listen(Future<void> Function() onAlert);
}

class FcmPushAlerts implements PushAlerts {
  FcmPushAlerts(this._store);
  final LocalStore _store;

  final _subscriptions = <StreamSubscription<Object?>>[];
  ReceivePort? _port;

  SupabaseClient get _client => Supabase.instance.client;

  @override
  Future<bool> isEnabled() async => alertsSupported && await _store.setting(alertsEnabledKey) == '1';

  @override
  Future<void> enable() async {
    if (!alertsSupported) throw UnsupportedError('alerts are Android only');
    final settings = await FirebaseMessaging.instance.requestPermission();
    if (settings.authorizationStatus == AuthorizationStatus.denied) {
      throw const NotificationsDeniedException();
    }
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) throw StateError('no FCM token');
    await _register(token);
    await _store.setSetting(alertsEnabledKey, '1');
  }

  @override
  Future<void> disable() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token != null) await _client.from('push_tokens').delete().eq('token', token);
    await FirebaseMessaging.instance.deleteToken();
    await _store.setSetting(alertsEnabledKey, '0');
  }

  Future<void> _register(String token) =>
      _client.from('push_tokens').upsert({'token': token, 'platform': 'android'}, onConflict: 'token');

  @override
  void listen(Future<void> Function() onAlert) {
    // Firebase is only set up by initPushAlerts (not in tests, not off Android).
    if (!alertsSupported || Firebase.apps.isEmpty || _port != null) return;

    Future<void> handle(String networkId) async {
      try {
        await showNewDeviceAlert(_client, networkId);
        await onAlert();
      } catch (e) {
        debugPrint('new-device alert: $e');
      }
    }

    final port = _port = ReceivePort();
    IsolateNameServer.removePortNameMapping(_portName);
    IsolateNameServer.registerPortWithName(port.sendPort, _portName);
    _subscriptions
      ..add(port.listen((msg) {
        if (msg case [final String networkId, final SendPort reply]) {
          reply.send(true);
          handle(networkId);
        }
      }))
      ..add(FirebaseMessaging.onMessage.listen((m) {
        final networkId = _networkOf(m);
        if (networkId != null) handle(networkId);
      }))
      ..add(FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
        if (await isEnabled()) await _register(token);
      }));
  }
}

final pushAlertsProvider = Provider<PushAlerts>((ref) => FcmPushAlerts(ref.read(localStoreProvider)));

final alertsEnabledProvider = FutureProvider<bool>((ref) => ref.read(pushAlertsProvider).isEnabled());
