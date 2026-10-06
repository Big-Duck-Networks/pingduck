import 'dart:async';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Whether the device is on a local network it can scan: Wi-Fi or Ethernet.
/// Mobile data alone does not count; there is no LAN behind it.
abstract interface class LanConnectivity {
  Future<bool> current();
  Stream<bool> changes();
}

class PlatformLanConnectivity implements LanConnectivity {
  PlatformLanConnectivity([Connectivity? connectivity]) : _c = connectivity ?? Connectivity();
  final Connectivity _c;

  static bool _onLan(List<ConnectivityResult> r) =>
      r.contains(ConnectivityResult.wifi) || r.contains(ConnectivityResult.ethernet);

  // Where the platform cannot tell (no plugin, e.g. in host tests), assume a
  // LAN rather than blanking the app; a failed scan still reports it.
  @override
  Future<bool> current() async {
    try {
      return _onLan(await _c.checkConnectivity());
    } on MissingPluginException {
      return true;
    } on PlatformException {
      return true;
    }
  }

  @override
  Stream<bool> changes() => _c.onConnectivityChanged.map(_onLan).handleError((Object _) {});
}

final lanConnectivityProvider = Provider<LanConnectivity>((ref) => PlatformLanConnectivity());

/// Live "on a LAN" flag; while unknown (first frame) it reads as connected.
final lanConnectedProvider = StreamProvider<bool>((ref) async* {
  final c = ref.watch(lanConnectivityProvider);
  yield await c.current();
  yield* c.changes().distinct();
});

extension LanConnectedX on AsyncValue<bool> {
  /// False only when the platform positively reports no Wi-Fi or Ethernet.
  bool get isOnLan => value ?? true;
}

/// Opens the system Wi-Fi panel (Android only; iOS has no public route there).
Future<void> openWifiSettings() async {
  if (!Platform.isAndroid) return;
  try {
    await const MethodChannel('pingduck/system').invokeMethod<void>('openWifiSettings');
  } on PlatformException {
    // No settings activity on this device; nothing useful to do.
  }
}

bool get canOpenWifiSettings => Platform.isAndroid;
