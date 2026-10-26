import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../core/constants/app_flavor.dart';
import '../../../core/constants/app_version.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/external_links.dart';

/// "About & contacts" screen, mirroring Fing's clean minimalist layout:
/// brand header, store rating, release notes, website, and share with a friend.
class AboutContactsScreen extends StatelessWidget {
  const AboutContactsScreen({super.key});

  static const company = 'Big Duck Networks';
  static const shareMessage =
      'Check out PingDuck — Fast network discovery & device monitoring: https://pingduck.app';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: PingDuckColors.canvas,
      appBar: AppBar(
        backgroundColor: PingDuckColors.canvas,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
        title: Text('About & contacts', style: PdText.headlineSm),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          // App header: Logo, Name, Version
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [
                DuckLogo(size: 52, isDev: AppFlavor.current.isDev),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        AppFlavor.current.isDev ? 'PingDuck Dev' : 'PingDuck',
                        style: PdText.headlineMd,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        AppVersion.display,
                        style: PdText.bodyMd.copyWith(color: PingDuckColors.inkMuted),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 24, thickness: 1, color: PingDuckColors.hairline),

          // 1. Rate on the Store
          _ContactActionRow(
            icon: Icons.emoji_events_outlined,
            title: 'Rate PingDuck on the Store',
            subtitle: 'Rate and review this App on the Store',
            onTap: () => openPlayStore(),
          ),

          // 2. Release notes
          _ContactActionRow(
            icon: Icons.description_outlined,
            title: 'Release notes',
            subtitle: 'Show the new content of this version',
            onTap: () => _showReleaseNotes(context),
          ),

          // 3. Website
          _ContactActionRow(
            icon: Icons.public_outlined,
            title: 'Website',
            subtitle: 'Visit PingDuck website.',
            onTap: () => openExternalUrl(websiteUrl),
          ),

          // 4. Tell a friend
          _ContactActionRow(
            icon: Icons.share_outlined,
            title: 'Tell a friend',
            subtitle: 'Share PingDuck with your friends on email or social networks.',
            onTap: () => _shareApp(context),
          ),

          const SizedBox(height: 40),

          // Subtle legal & licenses footer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Column(
              children: [
                TextButton(
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.padded,
                  ),
                  onPressed: () => showLicensePage(
                    context: context,
                    applicationName: AppFlavor.current.isDev ? 'PingDuck Dev' : 'PingDuck',
                    applicationVersion: AppVersion.display,
                    applicationLegalese: '© ${DateTime.now().year} $company',
                  ),
                  child: Text(
                    'Third-party notices & licenses',
                    style: PdText.bodySm.copyWith(color: PingDuckColors.inkSecondary),
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  '© ${DateTime.now().year} $company. All rights reserved.',
                  style: PdText.bodySm.copyWith(color: PingDuckColors.inkMuted),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  static Future<void> _shareApp(BuildContext context) async {
    if (Platform.isAndroid) {
      try {
        await const MethodChannel('pingduck/system').invokeMethod<void>(
          'shareText',
          {'text': shareMessage},
        );
        return;
      } catch (_) {}
    }

    // Fallback: Copy share link to clipboard and show toast
    await Clipboard.setData(const ClipboardData(text: shareMessage));
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Share link copied to clipboard!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  static void _showReleaseNotes(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: PingDuckColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('RELEASE NOTES', style: PdText.labelLg),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Version ${AppVersion.display}',
                style: PdText.headlineSm,
              ),
              const SizedBox(height: 16),
              const _ReleaseNoteBullet(
                title: 'Smart Device & OS Recognition',
                description:
                    'Identifies connected network hardware and operating systems with high-resolution brand logos and recognizable names.',
              ),
              const SizedBox(height: 12),
              const _ReleaseNoteBullet(
                title: 'One-Tap Confirmation',
                description:
                    'Confirm detected device identity with a single tap to tune network intelligence and enhance look-alike discovery.',
              ),
              const SizedBox(height: 12),
              const _ReleaseNoteBullet(
                title: 'Deep Hardware Inspector',
                description:
                    'Inspect network telemetry, response TTLs, SSDP server strings, MAC vendor data, and port profiles.',
              ),
              const SizedBox(height: 12),
              const _ReleaseNoteBullet(
                title: 'Performance & Architecture Polish',
                description:
                    'Optimized scan concurrency, crisp SVG brand badges, and background alert stability.',
              ),
              const SizedBox(height: 24),
              PdButton(
                label: 'Close',
                style: PdButtonStyle.primary,
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ContactActionRow extends StatelessWidget {
  const _ContactActionRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
        child: Row(
          children: [
            Icon(icon, size: 24, color: PingDuckColors.ink),
            const SizedBox(width: 20),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: PdText.headlineSm.copyWith(fontSize: 16)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: PdText.bodySm),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReleaseNoteBullet extends StatelessWidget {
  const _ReleaseNoteBullet({required this.title, required this.description});

  final String title;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.only(top: 4),
          child: Icon(Icons.check_circle_outline, size: 16, color: PingDuckColors.live),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: PdText.labelLg.copyWith(fontSize: 13)),
              const SizedBox(height: 2),
              Text(description, style: PdText.bodySm),
            ],
          ),
        ),
      ],
    );
  }
}
