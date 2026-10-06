import 'package:flutter/material.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../tools/presentation/tools_screen.dart';

/// The Homelab Agent tool. A placeholder until the agent ships (Phase 4):
/// explains what pairing unlocks rather than showing sample alerts that look
/// real.
class AgentScreen extends StatelessWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ToolBreadcrumb(Tool.agent),
        const SizedBox(height: 8),
        PdPanel(
          background: PingDuckColors.canvas,
          child: Row(children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(color: PingDuckColors.surface1, border: Border.all(color: PingDuckColors.partition)),
              child: const Icon(Icons.dns_outlined, color: PingDuckColors.inkMuted),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('DOCKER SNIFFER DAEMON', style: PdText.labelSm),
                const SizedBox(height: 2),
                Text('No agent paired', style: PdText.headlineSm),
              ]),
            ),
            const PdChip('OFFLINE'),
          ]),
        ),
        const SizedBox(height: 16),
        PdPanel(
          title: 'What the agent adds',
          icon: Icons.shield_outlined,
          accent: PingDuckColors.ink,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            for (final (icon, title, body) in const [
              (Icons.memory, 'MAC addresses & vendors',
                  'Phones hide the ARP table. The agent sniffs ARP on your LAN, so every device gets its hardware address and maker.'),
              (Icons.notification_important_outlined, 'Intrusion alerts',
                  'A push notification when an unknown device joins, the gateway MAC changes, or two hosts claim one IP.'),
              (Icons.schedule, '24/7 monitoring',
                  'Scans on an interval from a homelab box and syncs history, even when your phone is off the network.'),
            ])
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(icon, size: 20, color: PingDuckColors.live),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(title, style: PdText.labelLg),
                      const SizedBox(height: 2),
                      Text(body, style: PdText.bodySm),
                    ]),
                  ),
                ]),
              ),
          ]),
        ),
        const SizedBox(height: 16),
        PdPanel(
          title: 'Run it',
          icon: Icons.terminal,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('On a Linux box or Proxmox VM on this network:', style: PdText.bodySm),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(10),
              color: PingDuckColors.surface2,
              child: Text(
                'docker run --rm --net=host \\\n  --cap-add=NET_RAW --cap-add=NET_ADMIN \\\n  pingduck-agent',
                style: PdText.code,
              ),
            ),
            const SizedBox(height: 12),
            const PdButton(label: 'Pair agent · coming soon', icon: Icons.qr_code_2),
          ]),
        ),
      ],
    );
  }
}
