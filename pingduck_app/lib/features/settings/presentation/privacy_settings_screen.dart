import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../services/external_links.dart';
import '../../scanner/application/scan_controller.dart';

const crashReportingKey = 'crashReporting';

/// Whether crash reporting is enabled (defaults to true / '1').
final crashReportingProvider = FutureProvider<bool>((ref) async {
  final store = ref.read(localStoreProvider);
  final val = await store.setting(crashReportingKey);
  return val != '0';
});

/// Screen displaying Analytics Settings (Crash reporting toggle) and
/// Legal / Policy links (Privacy Policy and Terms of Service).
class PrivacySettingsScreen extends ConsumerWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appThemeModeProvider);
    final theme = Theme.of(context);
    final isDark = PingDuckColors.isDark;
    final crashReporting = ref.watch(crashReportingProvider).value ?? true;

    final sectionDividerColor = isDark ? const Color(0xFF1A1A1A) : const Color(0xFFF1F3F5);

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(
          'Privacy settings',
          style: TextStyle(
            color: PingDuckColors.ink,
            fontWeight: FontWeight.bold,
          ),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: Icon(Icons.arrow_back, color: PingDuckColors.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
        elevation: 0,
        backgroundColor: theme.scaffoldBackgroundColor,
      ),
      body: ListView(
        padding: EdgeInsets.zero,
        children: [
          // -------------------------------------------------------------
          // Section 1: Analytics Settings
          // -------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Analytics Settings',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: PingDuckColors.ink,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Crash reporting',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w600,
                          color: PingDuckColors.ink,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Send reports to developers when the App crashes.',
                        style: TextStyle(
                          fontSize: 14,
                          color: PingDuckColors.inkMuted,
                          height: 1.3,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Switch(
                  key: const Key('crash_reporting_switch'),
                  value: crashReporting,
                  activeTrackColor: PingDuckColors.route,
                  onChanged: (enabled) async {
                    await ref.read(localStoreProvider).setSetting(
                          crashReportingKey,
                          enabled ? '1' : '0',
                        );
                    ref.invalidate(crashReportingProvider);
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Thick Section Separator
          Container(
            height: 14,
            color: sectionDividerColor,
          ),

          // -------------------------------------------------------------
          // Section 2: Privacy Policy
          // -------------------------------------------------------------
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'Privacy policy',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: PingDuckColors.ink,
              ),
            ),
          ),
          InkWell(
            onTap: () => openExternalUrl(privacyUrl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Privacy policy',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: PingDuckColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          privacyUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: PingDuckColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: PingDuckColors.inkMuted.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
          Divider(
            height: 1,
            thickness: 1,
            indent: 16,
            endIndent: 0,
            color: PingDuckColors.hairline,
          ),
          InkWell(
            onTap: () => openExternalUrl(termsUrl),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Terms of service',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: PingDuckColors.ink,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          termsUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 14,
                            color: PingDuckColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(
                    Icons.chevron_right,
                    color: PingDuckColors.inkMuted.withValues(alpha: 0.7),
                    size: 22,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
