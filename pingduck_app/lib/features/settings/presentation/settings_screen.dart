import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/scan_quota.dart';
import '../../scanner/application/scan_controller.dart';

export '../../../services/scan_quota.dart'
    show autoScanOnLaunchKey, defaultAutoScanOnLaunch, isAutoScanOnLaunchEnabled, setAutoScanOnLaunch;

/// Per-host reply wait for a scan, in seconds; the scanner reads the same key.
const scanTimeoutKey = 'scanTimeoutSec';
const scanTimeoutChoices = [1, 3, 5, 10];
const defaultScanTimeout = 3;

final scanTimeoutProvider = FutureProvider<int>((ref) async =>
    int.tryParse(await ref.read(localStoreProvider).setting(scanTimeoutKey) ?? '') ?? defaultScanTimeout);

final autoScanOnLaunchProvider = FutureProvider<bool>((ref) async {
  final store = ref.read(localStoreProvider);
  return isAutoScanOnLaunchEnabled(store);
});

final isPremiumProvider = FutureProvider<bool>((ref) async {
  final store = ref.read(localStoreProvider);
  return isPremiumUser(store);
});

/// App settings. Scan behaviour works today; agent, sync and notifications
/// arrive with Phase 4 and show as disabled rows until then.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeout = ref.watch(scanTimeoutProvider).value ?? defaultScanTimeout;
    final autoScan = ref.watch(autoScanOnLaunchProvider).value ?? defaultAutoScanOnLaunch;
    final isPremium = ref.watch(isPremiumProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(
        title: Text('APP SETTINGS', style: PdText.labelLg),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          PdPanel(
            title: 'Scanning',
            icon: Icons.radar,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Reply timeout', style: PdText.headlineSm),
                const SizedBox(height: 2),
                Text('How long to wait for slow devices. Longer finds more on busy networks but scans slower.',
                    style: PdText.bodySm),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final s in scanTimeoutChoices)
                      ChoiceChip(
                        label: Text('${s}s'),
                        selected: s == timeout,
                        onSelected: (_) async {
                          await ref.read(localStoreProvider).setSetting(scanTimeoutKey, '$s');
                          ref.invalidate(scanTimeoutProvider);
                        },
                      ),
                  ],
                ),
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 14),
                  child: Divider(),
                ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Wrap(
                            crossAxisAlignment: WrapCrossAlignment.center,
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              Text('Auto-scan on launch', style: PdText.headlineSm),
                              const PdChip('PREMIUM', tone: PdTone.route),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPremium
                                ? 'Automatically start a network scan when the app opens.'
                                : 'Automatically start a network scan when the app opens (Premium plan required).',
                            style: PdText.bodySm,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Switch(
                      key: const Key('auto_scan_switch'),
                      value: autoScan,
                      onChanged: (enabled) async {
                        final store = ref.read(localStoreProvider);
                        await setAutoScanOnLaunch(store, enabled);
                        if (enabled) {
                          await setIsPremiumUser(store, true);
                          await store.setSetting('quotaLimit', 'none');
                        }
                        ref.invalidate(autoScanOnLaunchProvider);
                        ref.invalidate(isPremiumProvider);
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          const PdPanel(
            title: 'Cloud & alerts',
            icon: Icons.cloud_outlined,
            trailing: PdChip('PHASE 4'),
            child: Column(
              children: [
                _ComingRow(icon: Icons.memory, title: 'Homelab Agent', sub: 'Pair an agent for MACs and alerts'),
                _ComingRow(icon: Icons.sync, title: 'Cloud sync', sub: 'Sync inventory across devices'),
                _ComingRow(
                    icon: Icons.notifications_outlined, title: 'Notifications', sub: 'New-device intrusion alerts'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ComingRow extends StatelessWidget {
  const _ComingRow({required this.icon, required this.title, required this.sub});
  final IconData icon;
  final String title;
  final String sub;

  @override
  Widget build(BuildContext context) => ListTile(
        enabled: false,
        contentPadding: EdgeInsets.zero,
        leading: Icon(icon, color: PingDuckColors.inkMuted),
        title: Text(title, style: PdText.bodyMd.copyWith(color: PingDuckColors.inkMuted)),
        subtitle: Text(sub, style: PdText.bodySm),
        trailing: const Switch(value: false, onChanged: null),
      );
}
