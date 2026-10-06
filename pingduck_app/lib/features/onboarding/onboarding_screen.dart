import 'dart:io';

import 'package:flutter/material.dart';

import '../../core/theme/pingduck_colors.dart';
import '../../core/theme/pingduck_theme.dart';
import '../../core/widgets/pd_widgets.dart';

/// First launch: what scanning does, why the OS asks for local network
/// access, and why MAC addresses need the agent.
class OnboardingScreen extends StatelessWidget {
  const OnboardingScreen({super.key, required this.onDone});

  /// Called when the user starts the first scan.
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final points = [
      (Icons.radar, 'Map your network',
          'PingDuck pings every address on your Wi-Fi and listens for devices announcing themselves (mDNS, UPnP). Nothing leaves your network.'),
      (Icons.lock_open_outlined, 'Permissions',
          Platform.isIOS
              ? 'iOS will ask for local network access, which scanning needs, and for location, which only reveals your Wi-Fi name. Your location is never recorded.'
              : 'Android will ask for location once. It only reveals your Wi-Fi name; your location is never recorded. Say no and scans still work.'),
      (Icons.memory, 'MAC addresses',
          'Phones are not allowed to read hardware addresses. Pair the homelab agent later to see MACs and vendors for every device.'),
    ];
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 24),
            const Align(alignment: Alignment.centerLeft, child: DuckLogo(size: 64)),
            const SizedBox(height: 20),
            Text('PINGDUCK', style: PdText.displayMobile.copyWith(color: PingDuckColors.live, letterSpacing: 2)),
            Text('LAN RECON', style: PdText.labelLg.copyWith(letterSpacing: 3, color: PingDuckColors.inkSecondary)),
            const SizedBox(height: 12),
            Text('Quack. Let\'s see who\'s on your network.', style: PdText.bodyLg),
            const SizedBox(height: 28),
            for (final (icon, title, body) in points)
              Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: PingDuckColors.surface1,
                  border: Border.all(color: PingDuckColors.partition),
                ),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, color: PingDuckColors.live),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title.toUpperCase(), style: PdText.labelLg),
                      const SizedBox(height: 4),
                      Text(body, style: PdText.bodySm),
                    ]),
                  ),
                ]),
              ),
            const SizedBox(height: 20),
            PdButton(label: 'Start first scan', icon: Icons.radar, style: PdButtonStyle.primary, height: 52, onPressed: onDone),
          ]),
        ),
      ),
    );
  }
}
