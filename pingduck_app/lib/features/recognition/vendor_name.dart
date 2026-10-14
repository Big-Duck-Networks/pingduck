import 'recognition_rules.dart';

/// The name people know a MAC vendor by. The IEEE registry lists the
/// company that registered the address block, often a factory or a legal
/// entity: "LCFC(Hefei) Electronics Technology co., ltd" is Lenovo.
abstract final class VendorName {
  /// "LCFC(Hefei) Electronics…" → "Lenovo", "Espressif Inc." → "Espressif",
  /// "Acme Widgets Co., Ltd." → "Acme Widgets". The randomized-MAC
  /// placeholder is returned as is.
  static String? of(String? vendor) {
    if (vendor == null || vendor.isEmpty) return null;
    if (vendor.startsWith('Private')) return vendor;
    return brand(vendor) ?? module(vendor) ?? tidy(vendor);
  }

  /// The product brand, when the vendor is a known brand or makes for one.
  static String? brand(String vendor) => _match(brandRules, vendor);

  /// The maker, when the vendor builds network modules rather than products.
  static String? module(String vendor) => _match(moduleMakers, vendor);

  /// Registry names without the legal suffix: "Proxmox Server Solutions GmbH"
  /// → "Proxmox Server Solutions".
  static String tidy(String vendor) {
    var v = vendor.replaceAll(RegExp(r'\s*\(.*?\)'), '');
    v = v.replaceAll(
        RegExp(r'[,.]?\s*(co\.?,?\s*ltd\.?|inc\.?|corp\.?|corporation|gmbh|ltd\.?|llc|s\.?a\.?|b\.?v\.?|ag|limited)\.?$',
            caseSensitive: false),
        '');
    return v.trim().replaceAll(RegExp(r'[,.]$'), '');
  }

  static String? _match(List<BrandRule> rules, String vendor) {
    final v = vendor.toLowerCase();
    for (final r in rules) {
      if (RegExp(r.pattern).hasMatch(v)) return r.name;
    }
    return null;
  }
}
