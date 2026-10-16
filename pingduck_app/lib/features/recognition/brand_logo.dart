import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../../core/theme/pingduck_colors.dart';

/// A brand or OS mark from assets/logos (Simple Icons 16.35.0, CC0; the
/// marks remain their owners' trademarks and only identify the device).
class BrandLogo extends StatelessWidget {
  const BrandLogo._(this.slug, this.color);

  final String slug;
  final Color color;

  static const size = 52.0;

  /// The logo for a recognized brand or OS name, or null when none is bundled.
  static BrandLogo? forName(String name) {
    final entry = _logos[name];
    return entry == null ? null : BrandLogo._(entry.$1, entry.$2 ?? PingDuckColors.ink);
  }

  /// Name → (asset slug, brand color). Brands whose color would vanish on a
  /// light surface (white, pale grey, yellow) use ink instead.
  static const _logos = <String, (String, Color?)>{
    'Apple': ('apple', null),
    'iOS': ('ios', null),
    'iPadOS': ('ios', null),
    'macOS': ('macos', null),
    'tvOS': ('apple', null),
    'audioOS': ('apple', null),
    'Google': ('google', Color(0xFF4285F4)),
    'Android': ('android', Color(0xFF3DDC84)),
    'Amazon': ('amazon', Color(0xFFFF9900)),
    'Samsung': ('samsung', Color(0xFF1428A0)),
    'Lenovo': ('lenovo', Color(0xFFE2231A)),
    'HP': ('hp', Color(0xFF0096D6)),
    'Dell': ('dell', Color(0xFF007DB8)),
    'ASUS': ('asus', null),
    'MSI': ('msi', Color(0xFFFF0000)),
    'Intel': ('intel', Color(0xFF0071C5)),
    'TP-Link': ('tplink', Color(0xFF4ACBD6)),
    'Netgear': ('netgear', Color(0xFF2C262D)),
    'Ubiquiti': ('ubiquiti', Color(0xFF0559C9)),
    'Synology': ('synology', null),
    'QNAP': ('qnap', Color(0xFF0C2E82)),
    'Raspberry Pi': ('raspberrypi', Color(0xFFA22846)),
    'Sonos': ('sonos', null),
    'Roku': ('roku', Color(0xFF662D91)),
    'Sony': ('sony', null),
    'LG': ('lg', Color(0xFFA50034)),
    'Philips Hue': ('philipshue', Color(0xFF0065D3)),
    'Epson': ('epson', Color(0xFF003399)),
    'Xiaomi': ('xiaomi', Color(0xFFFF6900)),
    'OnePlus': ('oneplus', Color(0xFFF5010C)),
    'Nintendo': ('nintendo', Color(0xFFE60012)),
    'Proxmox': ('proxmox', Color(0xFFE57000)),
    'Linux': ('linux', null),
    'Windows': ('windows', Color(0xFF0078D4)),
  };

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/logos/$slug.svg',
        width: size,
        height: size,
        colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
        semanticsLabel: null,
        excludeFromSemantics: true,
      );
}
