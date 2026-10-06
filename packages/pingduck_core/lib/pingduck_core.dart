/// Dart API for pingduck-core, the PingDuck LAN discovery engine.
///
/// Blocking native calls run on short-lived helper isolates, so nothing here
/// blocks the UI isolate. Discovery results stream back as [PdDevice]s.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:ffi/ffi.dart';

import 'src/bindings.g.dart';

export 'src/bindings.g.dart'
    show
        PD_SCAN_ICMP,
        PD_SCAN_MDNS,
        PD_SCAN_SSDP,
        PD_SCAN_ARP,
        PD_SCAN_DNS,
        PD_SCAN_ARP_CACHE,
        PD_SCAN_DEFAULT,
        PD_SRC_ICMP,
        PD_SRC_MDNS,
        PD_SRC_SSDP,
        PD_SRC_ARP,
        PD_SRC_DNS;

/// A device as reported by the core. Each report for an IP carries the full
/// merged record, so consumers can upsert by [ip].
class PdDevice {
  const PdDevice({
    required this.ip,
    this.mac,
    this.hostname,
    this.vendor,
    this.model,
    this.services = const [],
    this.rttMs,
    this.sources = 0,
  });

  final String ip;
  final String? mac;
  final String? hostname;
  final String? vendor;
  final String? model;
  final List<String> services;
  final int? rttMs;

  /// `PD_SRC_*` bitmask.
  final int sources;

  factory PdDevice._fromNative(pd_device d) {
    final services = _string(d.services, PD_SERVICES_LEN);
    return PdDevice(
      ip: _string(d.ip, PD_IP_LEN),
      mac: _nonEmpty(_string(d.mac, PD_MAC_LEN)),
      hostname: _nonEmpty(_string(d.hostname, PD_HOSTNAME_LEN)),
      vendor: _nonEmpty(_string(d.vendor, PD_VENDOR_LEN)),
      model: _nonEmpty(_string(d.model, PD_MODEL_LEN)),
      services: services.isEmpty ? const [] : services.split(','),
      rttMs: d.rtt_ms >= 0 ? d.rtt_ms : null,
      sources: d.sources,
    );
  }

  @override
  String toString() => 'PdDevice($ip, ${hostname ?? '-'}, ${vendor ?? '-'})';
}

/// A local IPv4 interface.
class PdInterface {
  const PdInterface({
    required this.name,
    required this.ip,
    required this.netmask,
    required this.prefixLength,
    this.gateway,
    this.dns,
    this.mac,
  });

  final String name;
  final String ip;
  final String netmask;
  final int prefixLength;
  final String? gateway;
  final String? dns;
  final String? mac;

  /// The interface's subnet in CIDR notation, e.g. `10.42.0.0/24`.
  String get cidr {
    final parts = ip.split('.').map(int.parse).toList();
    final addr = parts.fold<int>(0, (a, b) => (a << 8) | b);
    final mask = prefixLength == 0 ? 0 : (0xFFFFFFFF << (32 - prefixLength)) & 0xFFFFFFFF;
    final net = addr & mask;
    return '${net >> 24 & 255}.${net >> 16 & 255}.${net >> 8 & 255}.${net & 255}/$prefixLength';
  }

  factory PdInterface._fromNative(pd_interface f) => PdInterface(
        name: _string(f.name, 64),
        ip: _string(f.ip, PD_IP_LEN),
        netmask: _string(f.netmask, PD_IP_LEN),
        prefixLength: f.prefix_len,
        gateway: _nonEmpty(_string(f.gateway, PD_IP_LEN)),
        dns: _nonEmpty(_string(f.dns, PD_IP_LEN)),
        mac: _nonEmpty(_string(f.mac, PD_MAC_LEN)),
      );
}

/// A negative `PD_ERR_*` code from the core.
class PingDuckException implements Exception {
  PingDuckException(this.code, [String? operation])
      : message = '${operation == null ? '' : '$operation: '}${_errorText(code)}';

  final int code;
  final String message;

  bool get isPermission => code == PD_ERR_PERMISSION;

  @override
  String toString() => 'PingDuckException($code): $message';
}

/// How a scan ended.
class ScanOutcome {
  const ScanOutcome({required this.deviceCount, required this.cancelled});
  final int deviceCount;
  final bool cancelled;
}

/// A running discovery call. [devices] delivers every new or updated device;
/// [done] completes when the core returns.
class ScanSession {
  ScanSession._(this.devices, this.done);

  final Stream<PdDevice> devices;
  final Future<ScanOutcome> done;

  /// Asks the core to stop. Cancellation is global in the core: it also stops
  /// any other discovery call running at the same moment.
  void cancel() => PingDuckCore.instance.cancel();
}

/// Entry point to the native engine.
class PingDuckCore {
  PingDuckCore._();

  static final PingDuckCore instance = PingDuckCore._();

  String get version => _bindings.pd_version().cast<Utf8>().toDartString();

  /// Requests that running discovery calls return early.
  void cancel() => _bindings.pd_cancel();

  /// The interface most likely to be the LAN, or null when there is none
  /// (airplane mode, no Wi-Fi). Fast enough to call on the UI isolate.
  PdInterface? defaultInterface() {
    final out = calloc<pd_interface>();
    try {
      return _bindings.pd_default_interface(out) == PD_OK ? PdInterface._fromNative(out.ref) : null;
    } finally {
      calloc.free(out);
    }
  }

  List<PdInterface> interfaces() {
    const max = 32;
    final out = calloc<pd_interface>(max);
    try {
      final n = _bindings.pd_list_interfaces(out, max);
      return [for (var i = 0; i < n; i++) PdInterface._fromNative(out[i])];
    } finally {
      calloc.free(out);
    }
  }

  /// Gateway and DNS server known to the platform but hidden from native code
  /// (Android 10+). Pass nulls to clear them.
  void setLanHints({String? gateway, String? dns}) {
    using((arena) {
      final rc = _bindings.pd_set_lan_hints(
        gateway == null ? nullptr : gateway.toNativeUtf8(allocator: arena).cast(),
        dns == null ? nullptr : dns.toNativeUtf8(allocator: arena).cast(),
      );
      if (rc < 0) throw PingDuckException(rc, 'setLanHints');
    });
  }

  /// Loads the IEEE OUI registry from CSV text (e.g. a bundled asset).
  /// Parsing takes a few hundred milliseconds on slow phones, so it runs on
  /// a helper isolate. Returns the number of entries loaded.
  Future<int> loadOui(Uint8List csv) async {
    final buf = malloc<Uint8>(csv.length);
    buf.asTypedList(csv.length).setAll(0, csv);
    final address = buf.address, length = csv.length;
    try {
      final rc = await Isolate.run(
        () => _openBindings().pd_oui_load_buffer(Pointer<Char>.fromAddress(address), length),
      );
      if (rc < 0) throw PingDuckException(rc, 'loadOui');
      return rc;
    } finally {
      malloc.free(buf);
    }
  }

  /// Runs every discovery method selected by [flags] (`PD_SCAN_*`) in
  /// parallel. [cidr] defaults to the default interface's subnet.
  ScanSession scan({String? cidr, Duration timeout = const Duration(seconds: 3), int flags = PD_SCAN_DEFAULT}) =>
      _discover('scan', (b, cb, user) {
        return using((arena) => b.pd_scan(
              cidr == null ? nullptr : cidr.toNativeUtf8(allocator: arena).cast(),
              timeout.inMilliseconds,
              flags,
              cb,
              user,
            ));
      });

  /// mDNS / DNS-SD discovery only.
  ScanSession mdns({Duration timeout = const Duration(seconds: 3)}) =>
      _discover('mdns', (b, cb, user) => b.pd_mdns_discover(timeout.inMilliseconds, cb, user));

  /// SSDP / UPnP discovery only.
  ScanSession ssdp({Duration timeout = const Duration(seconds: 3)}) =>
      _discover('ssdp', (b, cb, user) => b.pd_ssdp_discover(timeout.inMilliseconds, cb, user));

  /// Round-trip time to [ip], or null when it does not answer.
  Future<Duration?> ping(String ip, {Duration timeout = const Duration(seconds: 1)}) async {
    final ms = timeout.inMilliseconds;
    final rc = await Isolate.run(() => using((a) => _openBindings().pd_ping(ip.toNativeUtf8(allocator: a).cast(), ms)));
    if (rc >= 0) return Duration(milliseconds: rc);
    if (rc == PD_ERR_TIMEOUT) return null;
    throw PingDuckException(rc, 'ping');
  }

  /// TCP connect scan. Returns the subset of [ports] that accepted.
  Future<Set<int>> openPorts(String ip, List<int> ports, {Duration timeout = const Duration(milliseconds: 800)}) async {
    final ms = timeout.inMilliseconds;
    final result = await Isolate.run(() {
      return using((a) {
        final p = a<Uint16>(ports.length);
        final open = a<Uint8>(ports.length);
        for (var i = 0; i < ports.length; i++) {
          p[i] = ports[i];
        }
        final rc = _openBindings().pd_port_scan(ip.toNativeUtf8(allocator: a).cast(), p, ports.length, ms, open);
        if (rc < 0) return rc;
        return [for (var i = 0; i < ports.length; i++) if (open[i] != 0) ports[i]];
      });
    });
    if (result is int) throw PingDuckException(result, 'openPorts');
    return (result as List<int>).toSet();
  }

  /// Sends a Wake-on-LAN magic packet to [mac].
  Future<void> wakeOnLan(String mac, {String? broadcast}) async {
    final rc = await Isolate.run(() => using((a) => _openBindings().pd_wake_on_lan(
          mac.toNativeUtf8(allocator: a).cast(),
          broadcast == null ? nullptr : broadcast.toNativeUtf8(allocator: a).cast(),
        )));
    if (rc < 0) throw PingDuckException(rc, 'wakeOnLan');
  }

  /// Name for [ip] via the LAN DNS server, unicast mDNS or NetBIOS, or null.
  Future<String?> reverseLookup(String ip) => Isolate.run(() => using((a) {
        final out = a<Char>(PD_HOSTNAME_LEN);
        final rc = _openBindings().pd_reverse_dns(ip.toNativeUtf8(allocator: a).cast(), out, PD_HOSTNAME_LEN);
        return rc == PD_OK ? out.cast<Utf8>().toDartString() : null;
      }));

  /// Runs a blocking discovery call on a helper isolate and streams results.
  ///
  /// The core calls `pd_forward_copy` from its worker threads, which hands a
  /// heap copy of each device to a [NativeCallable.listener]; the listener
  /// runs on this isolate and frees the copy. After the call returns, the
  /// helper invokes the listener once more with `nullptr` as an end marker.
  /// Messages to one listener arrive in order, so the marker comes after
  /// every device, and only then is it safe to close the listener.
  ScanSession _discover(
    String operation,
    int Function(PingDuckBindings b, pd_device_cb cb, Pointer<Void> user) call,
  ) {
    final controller = StreamController<PdDevice>();
    final done = Completer<ScanOutcome>();
    var listenerFinished = false;
    int? rc;

    void finish() {
      if (!listenerFinished || rc == null || done.isCompleted) return;
      final code = rc!;
      controller.close();
      if (code >= 0 || code == PD_ERR_CANCELLED) {
        done.complete(ScanOutcome(deviceCount: code < 0 ? 0 : code, cancelled: code == PD_ERR_CANCELLED));
      } else {
        done.completeError(PingDuckException(code, operation));
      }
    }

    late final NativeCallable<pd_device_owned_cbFunction> listener;
    listener = NativeCallable<pd_device_owned_cbFunction>.listener((Pointer<pd_device> dev) {
      if (dev == nullptr) {
        listener.close();
        listenerFinished = true;
        finish();
        return;
      }
      try {
        if (!controller.isClosed) controller.add(PdDevice._fromNative(dev.ref));
      } finally {
        _bindings.pd_device_free(dev);
      }
    });

    _runDiscovery(call, _bindings.addresses.pd_forward_copy.address, listener.nativeFunction.address).then((value) {
      rc = value;
      finish();
    }, onError: (Object e, StackTrace s) {
      rc = PD_ERR_SOCKET;
      finish();
    });

    return ScanSession._(controller.stream, done.future);
  }
}

// ---- internals --------------------------------------------------------------

/// Kept out of [PingDuckCore._discover] on purpose: closures share their
/// enclosing function's captured context, and that one holds the listener and
/// stream controller, which cannot be sent to another isolate.
Future<int> _runDiscovery(
  int Function(PingDuckBindings b, pd_device_cb cb, Pointer<Void> user) call,
  int cbAddress,
  int userAddress,
) =>
    Isolate.run(() {
      final b = _openBindings();
      try {
        return call(b, Pointer.fromAddress(cbAddress), Pointer.fromAddress(userAddress));
      } finally {
        Pointer<NativeFunction<pd_device_owned_cbFunction>>.fromAddress(userAddress)
            .asFunction<void Function(Pointer<pd_device>)>()(nullptr);
      }
    });

const String _libName = 'pingduck';

DynamicLibrary _openLibrary() {
  if (Platform.isIOS || Platform.isMacOS) return DynamicLibrary.open('pingduck_core.framework/pingduck_core');
  if (Platform.isAndroid || Platform.isLinux) return DynamicLibrary.open('lib$_libName.so');
  if (Platform.isWindows) return DynamicLibrary.open('$_libName.dll');
  throw UnsupportedError('pingduck-core does not support ${Platform.operatingSystem}');
}

/// Helper isolates open their own handle; the OS returns the same library.
PingDuckBindings _openBindings() => PingDuckBindings(_openLibrary());

final PingDuckBindings _bindings = () {
  final b = _openBindings();
  b.pd_init();
  return b;
}();

String _string(Array<Char> chars, int capacity) {
  final bytes = <int>[];
  for (var i = 0; i < capacity; i++) {
    final c = chars[i];
    if (c == 0) break;
    bytes.add(c & 0xFF);
  }
  // Device names come off the network; never throw on bad UTF-8.
  return utf8.decode(bytes, allowMalformed: true);
}

String? _nonEmpty(String s) => s.isEmpty ? null : s;

String _errorText(int code) => switch (code) {
      PD_ERR_INVALID_ARG => 'invalid argument',
      PD_ERR_SOCKET => 'socket error',
      PD_ERR_UNSUPPORTED => 'not supported on this platform',
      PD_ERR_PERMISSION => 'permission denied',
      PD_ERR_NOT_FOUND => 'not found',
      PD_ERR_TIMEOUT => 'timed out',
      PD_ERR_CANCELLED => 'cancelled',
      _ => 'error $code',
    };
