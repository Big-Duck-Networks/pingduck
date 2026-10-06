import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pingduck_core/pingduck_core.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../scanner/application/scan_controller.dart';
import '../../settings/presentation/settings_screen.dart';

/// App version and build, e.g. "1.0.0 (1)"; null until loaded (or in tests).
final appVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final info = await PackageInfo.fromPlatform();
    return '${info.version} (${info.buildNumber})';
  } catch (_) {
    return null;
  }
});

/// Engine version, or null when the native library is not loaded (tests).
final coreVersionProvider = Provider<String?>((ref) {
  try {
    return PingDuckCore.instance.version;
  } catch (_) {
    return null;
  }
});

/// What the local cache holds; refreshed after scans and wipes.
final storageUsageProvider = FutureProvider<({int networks, int devices})>((ref) {
  ref.watch(scanControllerProvider.select((s) => (s.lastScanAt, s.devices.length)));
  return ref.read(localStoreProvider).usage();
});

/// Account tab. Sign-in and cloud sync arrive with Phase 4 (Supabase); until
/// then everything stays on this device, and this tab says so.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider);
    final scanning = ref.watch(scanControllerProvider.select((s) => s.isScanning));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PdSectionHeader(
          title: 'Account',
          icon: Icons.person_outline,
        ),
        const SizedBox(height: 16),
        PdPanel(
          background: PingDuckColors.canvas,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                      color: PingDuckColors.surface1,
                      border: Border.all(color: PingDuckColors.partition),
                    ),
                    child: const Icon(Icons.person_outline, color: PingDuckColors.inkMuted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Not signed in', style: PdText.headlineSm),
                        const SizedBox(height: 2),
                        Text('Everything stays on this device.', style: PdText.bodySm),
                      ],
                    ),
                  ),
                  const PdChip('LOCAL'),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'An account will sync your inventory across devices and connect the Homelab Agent for '
                'intrusion alerts.',
                style: PdText.bodySm,
              ),
              const SizedBox(height: 12),
              const PdButton(label: 'Sign in · coming with cloud sync', icon: Icons.login),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PdPanel(
          title: 'Settings',
          icon: Icons.tune_outlined,
          child: Semantics(
            button: true,
            label: 'App settings',
            child: InkWell(
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
              ),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: const BoxDecoration(
                  color: PingDuckColors.canvas,
                  border: Border.fromBorderSide(BorderSide(color: PingDuckColors.hairline)),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: PingDuckColors.surface1,
                        border: Border.all(color: PingDuckColors.partition),
                      ),
                      child: const Icon(Icons.tune_outlined, size: 20, color: PingDuckColors.ink),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('App settings', style: PdText.headlineSm),
                          const SizedBox(height: 2),
                          Text('Reply timeout, cloud sync and alerts', style: PdText.bodySm),
                        ],
                      ),
                    ),
                    const Icon(Icons.chevron_right, size: 20, color: PingDuckColors.inkSecondary),
                  ],
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 16),
        PdPanel(
          title: 'Data on this device',
          icon: Icons.storage_outlined,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PdField(
                label: 'Inventory',
                value: switch (usage) {
                  AsyncData(:final value) =>
                    '${value.devices} device${value.devices == 1 ? '' : 's'} on '
                        '${value.networks} network${value.networks == 1 ? '' : 's'}',
                  AsyncError() => 'unavailable',
                  _ => '…',
                },
                sub: 'names, notes and latency history included',
              ),
              const SizedBox(height: 12),
              PdButton(
                label: 'Clear device inventory',
                icon: Icons.delete_outline,
                style: PdButtonStyle.destructive,
                onPressed: scanning ? null : () => _confirmClear(context, ref),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _AboutPanel(),
      ],
    );
  }

  Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('CLEAR INVENTORY?', style: PdText.labelLg),
        content: Text(
          'Removes every remembered network and device, including your names and notes. The next scan '
          'starts fresh.',
          style: PdText.bodyMd,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('CLEAR', style: PdText.labelLg.copyWith(color: PingDuckColors.critical)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(scanControllerProvider.notifier).clearInventory();
    ref.invalidate(storageUsageProvider);
  }
}

/// Product identity, versions and legal. Third-party notices stay reachable
/// (BSD/MIT/OFL require it) but as a quiet text link, as in most commercial
/// apps.
class _AboutPanel extends ConsumerWidget {
  const _AboutPanel();

  static const company = 'Big Duck Networks';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final version = ref.watch(appVersionProvider).value;
    final core = ref.watch(coreVersionProvider);
    return PdPanel(
      background: PingDuckColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              const DuckLogo(size: 48),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('PingDuck', style: PdText.headlineMd),
                    Text('Network discovery & monitoring', style: PdText.bodySm),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: PdField(label: 'Version', value: version ?? '—')),
                const SizedBox(width: 8),
                Expanded(child: PdField(label: 'Discovery engine', value: core ?? '—')),
              ],
            ),
          ),
          const SizedBox(height: 14),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.verified_user_outlined, size: 18, color: PingDuckColors.live),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Scanning happens on your device and only contacts hosts on your local network. '
                  'No data leaves your phone unless you enable cloud sync.',
                  style: PdText.bodySm,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  '© ${DateTime.now().year} $company. All rights reserved.',
                  style: PdText.bodySm.copyWith(color: PingDuckColors.inkMuted),
                ),
              ),
              TextButton(
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.padded,
                ),
                onPressed: () => showLicensePage(
                  context: context,
                  applicationName: 'PingDuck',
                  applicationVersion: version,
                  applicationLegalese: '© ${DateTime.now().year} $company',
                ),
                child: Text('Third-party notices', style: PdText.bodySm.copyWith(color: PingDuckColors.inkSecondary)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
