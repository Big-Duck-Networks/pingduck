import '../scanner/domain/device_kind.dart';
import '../scanner/domain/discovered_device.dart';
import 'recognition_rules.dart';
import 'vendor_name.dart';

/// [user]: the user said so (Node Inspect's Edit).
/// [known]: the device said so itself (mDNS, UPnP, its SSDP server string).
/// [likely]: inferred from indirect signals (MAC vendor, hostname, TTL), or
/// learned from a label the user gave a device that looks the same.
enum Confidence { user, known, likely }

class Fact {
  const Fact(this.value, this.confidence);
  final String value;
  final Confidence confidence;

  bool get isGuess => confidence == Confidence.likely;
  bool get isUser => confidence == Confidence.user;

  @override
  bool operator ==(Object other) => other is Fact && other.value == value && other.confidence == confidence;

  @override
  int get hashCode => Object.hash(value, confidence);

  @override
  String toString() => '$value${isGuess ? ' (likely)' : ''}';
}

class OperatingSystem {
  const OperatingSystem(this.name, {this.vendor, this.version, required this.confidence});
  final String name;
  final String? vendor;
  final String? version;
  final Confidence confidence;

  bool get isGuess => confidence == Confidence.likely;
  bool get isUser => confidence == Confidence.user;

  @override
  String toString() => '$name${version == null ? '' : ' $version'}${isGuess ? ' (likely)' : ''}';
}

/// What a device is, as far as its own signals tell. Fields without a
/// signal behind them are null, never filled in.
class Recognition {
  const Recognition({this.brand, this.model, this.family, this.module, this.os});
  final Fact? brand;
  final Fact? model;
  final Fact? family;

  /// Maker of the network module when the MAC names the part, not the product.
  final Fact? module;
  final OperatingSystem? os;

  bool get hasDevice => brand != null || model != null || family != null || module != null;

  bool get hasGuesses =>
      (brand?.isGuess ?? false) ||
      (model?.isGuess ?? false) ||
      (family?.isGuess ?? false) ||
      (module?.isGuess ?? false) ||
      (os?.isGuess ?? false);
}

/// Turns the signals a scan collected into Brand, Model, Family and OS.
/// Pure and cheap, so it runs whenever a device is shown.
abstract final class Recognizer {
  /// Per field, the user's own label wins, then what the device said itself,
  /// then [learned] (the label of a device with the same fingerprint), then
  /// the guesses from indirect signals.
  static Recognition of(DiscoveredDevice d, DeviceKind kind, {DeviceLabel? learned}) {
    final auto = _auto(d, kind);
    final mine = d.label;
    if ((mine == null || mine.isEmpty) && (learned == null || learned.isEmpty)) return auto;

    Fact? pick(String? own, Fact? guess, String? taught) {
      if (own != null) return Fact(own, Confidence.user);
      if (guess != null && !guess.isGuess) return guess;
      if (taught != null) return Fact(taught, Confidence.likely);
      return guess;
    }

    final brand = pick(mine?.brand, auto.brand, learned?.brand);
    final model = pick(mine?.model, auto.model, learned?.model);
    var family = auto.family;
    if (model != auto.model && model != null) {
      final f = _family(brand?.value, _withoutBrand(model.value, brand?.value));
      family = f == null ? null : Fact(f, model.confidence);
    }

    var os = auto.os;
    if (mine?.os != null) {
      os = _labelOs(mine!.os!, Confidence.user);
    } else if ((os == null || os.isGuess) && learned?.os != null) {
      os = _labelOs(learned!.os!, Confidence.likely);
    }
    return Recognition(brand: brand, model: model, family: family, module: auto.module, os: os);
  }

  /// "windows 11" → Windows, version 11, by Microsoft.
  static OperatingSystem _labelOs(String text, Confidence confidence) {
    final m = RegExp(r'^(.*?)\s+v?(\d[\w.]*)$').firstMatch(text.trim());
    final typed = m?.group(1) ?? text.trim();
    final name = _osNames.firstWhere((n) => n.toLowerCase() == typed.toLowerCase(), orElse: () => typed);
    return OperatingSystem(name, vendor: _osVendor[name], version: m?.group(2), confidence: confidence);
  }

  static final _osNames = [..._osVendor.keys, 'Linux'];

  static Recognition _auto(DiscoveredDevice d, DeviceKind kind) {
    final selfDescribed = d.model != null && !_isServerBanner(d.model!) &&
        d.sources.any((s) => s == DiscoverySource.mdns || s == DiscoverySource.ssdp);
    final host = (d.hostname ?? '').toLowerCase();

    final appleModel = _appleModel(d.model);
    final vendor = d.hasPrivateMac ? null : d.vendor;
    final module = vendor == null ? null : VendorName.module(vendor);

    Fact? brand;
    if (appleModel != null) {
      brand = const Fact('Apple', Confidence.known);
    } else if (vendor != null && module == null) {
      brand = Fact(VendorName.brand(vendor) ?? VendorName.tidy(vendor), selfDescribed ? Confidence.known : Confidence.likely);
    } else {
      brand = _brandFromHostname(host);
    }

    Fact? model;
    if (appleModel != null) {
      model = Fact(appleModel, Confidence.known);
    } else if (d.model != null && !_isServerBanner(d.model!)) {
      model = Fact(_withoutBrand(d.model!, brand?.value), Confidence.known);
    }

    final family = _family(brand?.value, model?.value ?? host);
    return Recognition(
      brand: brand,
      model: model,
      family: family == null ? null : Fact(family, model != null ? Confidence.known : Confidence.likely),
      module: module == null ? null : Fact(module, Confidence.known),
      os: _os(d, kind, brand?.value, family, host),
    );
  }

  static OperatingSystem? _os(DiscoveredDevice d, DeviceKind kind, String? brand, String? family, String host) {
    OperatingSystem known(String name, {String? version}) =>
        OperatingSystem(name, vendor: _osVendor[name], version: version, confidence: Confidence.known);
    OperatingSystem likely(String name) => OperatingSystem(name, vendor: _osVendor[name], confidence: Confidence.likely);

    // 1. The device's own SSDP server string.
    final server = d.server?.toLowerCase() ?? '';
    final android = RegExp(r'android[\s-]?(\d+)').firstMatch(server);
    if (android != null) return known('Android', version: android.group(1));
    if (server.contains('windows')) return known('Windows');
    if (server.contains('darwin')) return known(_appleOs(family) ?? 'macOS');
    if (server.contains('tizen') || server.contains('samsung-linux')) return known('Tizen');

    // 2. An Apple product the device named itself.
    final appleOs = brand == 'Apple' ? _appleOs(family) : null;
    if (appleOs != null && d.model != null) return known(appleOs);

    if (server.contains('linux')) return known('Linux');

    // 3. Hostname conventions.
    if (RegExp(r'^(desktop|laptop)-[a-z0-9]{7}\b').hasMatch(host)) return likely('Windows');
    if (host.contains('iphone')) return likely('iOS');
    if (host.contains('ipad')) return likely('iPadOS');
    if (RegExp(r'macbook|imac|mac-?mini|mac-?studio').hasMatch(host)) return likely('macOS');
    if (RegExp(r'^android-|galaxy|pixel').hasMatch(host)) return likely('Android');
    if (appleOs != null) return likely(appleOs);

    // 4. What kind of device it is, and who made it.
    if (kind == DeviceKind.mobile && _androidBrands.contains(brand)) return likely('Android');
    if (_linuxBrands.contains(brand)) return likely('Linux');

    // 5. Initial TTL: Windows starts at 128. 64 (Linux, Android, Apple) and
    // 255 (network gear, embedded) are too broad to name an OS.
    final ttl = d.ttl;
    if (ttl != null && ttl > 64 && ttl <= 128) return likely('Windows');
    return null;
  }

  static const _osVendor = {
    'Windows': 'Microsoft',
    'Android': 'Google',
    'iOS': 'Apple',
    'iPadOS': 'Apple',
    'macOS': 'Apple',
    'tvOS': 'Apple',
    'audioOS': 'Apple',
    'Tizen': 'Samsung',
  };
  static const _androidBrands = {'Google', 'Samsung', 'OnePlus', 'Xiaomi', 'Lenovo'};
  static const _linuxBrands = {'Proxmox', 'Synology', 'QNAP', 'Raspberry Pi', 'Ubiquiti'};

  static String? _appleOs(String? family) => switch (family) {
        'iPhone' => 'iOS',
        'iPad' => 'iPadOS',
        'MacBook' || 'iMac' || 'Mac' => 'macOS',
        'Apple TV' => 'tvOS',
        'HomePod' => 'audioOS',
        _ => null,
      };

  /// "MacBookPro18,1" → "MacBook Pro". Longest identifier first, so
  /// "MacBookPro" wins over "MacBook" and "Mac".
  static String? _appleModel(String? model) {
    final m = model == null ? null : RegExp(r'^([A-Za-z]+)\d+,\d+$').firstMatch(model.trim());
    if (m == null) return null;
    final id = m.group(1)!;
    final keys = appleModels.keys.toList()..sort((a, b) => b.length.compareTo(a.length));
    for (final k in keys) {
      if (id == k) return appleModels[k];
    }
    return null;
  }

  static Fact? _brandFromHostname(String host) {
    if (RegExp(r'iphone|ipad|macbook|imac').hasMatch(host)) return const Fact('Apple', Confidence.likely);
    if (host.contains('galaxy')) return const Fact('Samsung', Confidence.likely);
    if (host.contains('pixel')) return const Fact('Google', Confidence.likely);
    return null;
  }

  static String? _family(String? brand, String model) {
    final m = model.toLowerCase().replaceAll(RegExp(r'[-_]'), ' ');
    for (final r in familyRules) {
      if ((brand == null || r.brand == brand) && RegExp(r.pattern).hasMatch(m)) return r.family;
    }
    return null;
  }

  /// "HP OfficeJet Pro 9010 series" with brand HP → "OfficeJet Pro 9010 series".
  static String _withoutBrand(String model, String? brand) {
    if (brand == null) return model;
    final prefix = '${brand.toLowerCase()} ';
    return model.toLowerCase().startsWith(prefix) && model.length > prefix.length
        ? model.substring(prefix.length)
        : model;
  }

  /// "Linux/5.15, UPnP/1.0, Chromecast/1.6": software, not a model. Older
  /// cores stored this in `model`.
  static bool _isServerBanner(String s) => s.contains('UPnP/');
}
