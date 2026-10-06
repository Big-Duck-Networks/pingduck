import 'dart:io';

import 'package:flutter/services.dart';
import 'package:network_info_plus/network_info_plus.dart';

/// The Wi-Fi network as the platform sees it. Android 10+ hides the gateway
/// from native code, so the scanner gets it from here.
class NetworkContext {
  const NetworkContext({this.ip, this.subnetMask, this.gateway});

  final String? ip;
  final String? subnetMask;
  final String? gateway;

  /// The subnet to sweep, e.g. `10.42.0.0/24`, or null if unknown.
  /// Clamped to /16 (the core's limit).
  String? get cidr {
    final addr = _parse(ip), mask = _parse(subnetMask);
    if (addr == null || mask == null || mask == 0) return null;
    var prefix = 0;
    while (prefix < 32 && (mask & (0x80000000 >> prefix)) != 0) {
      prefix++;
    }
    if (prefix < 16) prefix = 16;
    final m = (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF;
    return '${_format(addr & m)}/$prefix';
  }

  static int? _parse(String? s) {
    final parts = s?.split('.');
    if (parts == null || parts.length != 4) return null;
    var v = 0;
    for (final p in parts) {
      final n = int.tryParse(p);
      if (n == null || n < 0 || n > 255) return null;
      v = (v << 8) | n;
    }
    return v;
  }

  static String _format(int v) => '${v >> 24 & 255}.${v >> 16 & 255}.${v >> 8 & 255}.${v & 255}';
}

abstract interface class NetworkContextSource {
  /// The current Wi-Fi context, or null when the platform cannot tell
  /// (desktop, Ethernet); the core then picks the LAN interface itself.
  Future<NetworkContext?> current();
}

class PlatformNetworkContextSource implements NetworkContextSource {
  PlatformNetworkContextSource([NetworkInfo? info]) : _info = info ?? NetworkInfo();

  final NetworkInfo _info;

  @override
  Future<NetworkContext?> current() async {
    if (!Platform.isAndroid && !Platform.isIOS) return null;
    try {
      final ctx = NetworkContext(
        ip: await _info.getWifiIP(),
        subnetMask: await _info.getWifiSubmask(),
        gateway: await _info.getWifiGatewayIP(),
      );
      return ctx.ip == null ? null : ctx;
    } on PlatformException {
      return null;
    }
  }
}

/// Android drops inbound multicast (mDNS, SSDP replies) unless the app holds
/// a WifiManager.MulticastLock. Implemented in MainActivity; a no-op elsewhere.
class MulticastLock {
  const MulticastLock();

  static const _channel = MethodChannel('pingduck/multicast');

  Future<void> acquire() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('acquire');
  }

  Future<void> release() async {
    if (Platform.isAndroid) await _channel.invokeMethod<void>('release');
  }
}
