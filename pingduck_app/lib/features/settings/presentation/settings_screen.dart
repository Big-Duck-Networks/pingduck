import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/scan_quota.dart';
import '../../auth/account_auth.dart';
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

/// App settings. Organized into App settings (scanning timeout, auto-scan,
/// cloud sync and alerts) and User settings (profile and account deletion).
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return DefaultTabController(
      length: 2,
      initialIndex: initialIndex,
      child: Scaffold(
        appBar: AppBar(
          title: Text('APP SETTINGS', style: PdText.labelLg),
          leading: IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => Navigator.of(context).pop(),
          ),
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(44),
            child: Container(
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: PingDuckColors.hairline)),
              ),
              child: const TabBar(
                indicatorColor: PingDuckColors.live,
                indicatorWeight: 2,
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: PingDuckColors.live,
                unselectedLabelColor: PingDuckColors.inkSecondary,
                labelStyle: PdText.labelLg,
                unselectedLabelStyle: PdText.labelLg,
                tabs: [
                  Tab(text: 'APP'),
                  Tab(text: 'USER SETTINGS'),
                ],
              ),
            ),
          ),
        ),
        body: const TabBarView(
          children: [
            _AppSettingsTab(),
            _UserSettingsTab(),
          ],
        ),
      ),
    );
  }
}

class _AppSettingsTab extends ConsumerWidget {
  const _AppSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final timeout = ref.watch(scanTimeoutProvider).value ?? defaultScanTimeout;
    final autoScan = ref.watch(autoScanOnLaunchProvider).value ?? defaultAutoScanOnLaunch;
    final isPremium = ref.watch(isPremiumProvider).value ?? false;

    return ListView(
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
              Text(
                'How long to wait for slow devices. Longer finds more on busy networks but scans slower.',
                style: PdText.bodySm,
              ),
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
                icon: Icons.notifications_outlined,
                title: 'Notifications',
                sub: 'New-device intrusion alerts',
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _UserSettingsTab extends ConsumerWidget {
  const _UserSettingsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(accountEmailProvider).value;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        PdPanel(
          title: 'User Profile',
          icon: Icons.person_outline,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: PingDuckColors.surface1,
                      border: Border.all(color: PingDuckColors.partition),
                    ),
                    child: Icon(
                      email == null ? Icons.person_outline : Icons.person,
                      color: email == null ? PingDuckColors.inkMuted : PingDuckColors.ink,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          email ?? 'Not signed in',
                          style: PdText.headlineSm,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          email == null ? 'Local profile' : 'Signed in with email',
                          style: PdText.bodySm,
                        ),
                      ],
                    ),
                  ),
                  email == null ? const PdChip('LOCAL') : const PdChip('SIGNED IN', tone: PdTone.live),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                email == null
                    ? 'You are not signed in. An account is only needed to sync across devices or pair a Homelab Agent.'
                    : 'Your account is linked to this device. Scans and inventory stay local until cloud sync arrives.',
                style: PdText.bodySm,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        PdPanel(
          title: 'Account Deletion',
          icon: Icons.warning_amber_outlined,
          accent: PingDuckColors.critical,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Delete account', style: PdText.headlineSm),
              const SizedBox(height: 4),
              Text(
                'Permanently deletes your account and the email, plan and scan history stored with it. '
                'This cannot be undone. Devices and notes on this phone stay until you clear them. '
                'Subscriptions are billed by Apple or Google, so cancel any in the store first.',
                style: PdText.bodySm,
              ),
              const SizedBox(height: 14),
              if (email != null)
                PdButton(
                  label: 'Delete account',
                  icon: Icons.delete_outline,
                  style: PdButtonStyle.destructive,
                  onPressed: () => confirmDeleteAccount(context, ref),
                )
              else ...[
                const PdButton(
                  label: 'Delete account',
                  icon: Icons.delete_outline,
                  style: PdButtonStyle.destructive,
                  onPressed: null,
                ),
                const SizedBox(height: 6),
                Text(
                  'No signed-in account to delete.',
                  style: PdText.bodySm.copyWith(color: PingDuckColors.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Apple requires in-app deletion for any app that creates accounts.
Future<void> confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('DELETE ACCOUNT?', style: PdText.labelLg),
      content: Text(
        'Permanently deletes your account and the email, plan and scan history stored with it. This can’t be '
        'undone. Devices and notes on this phone stay until you clear them. Subscriptions are billed by Apple or '
        'Google, so cancel any in the store first.',
        style: PdText.bodyMd,
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('DELETE', style: PdText.labelLg.copyWith(color: PingDuckColors.critical)),
        ),
      ],
    ),
  );
  if (ok != true || !context.mounted) return;
  final messenger = ScaffoldMessenger.of(context)..hideCurrentSnackBar();
  try {
    await ref.read(accountAuthProvider).deleteAccount();
    messenger.showSnackBar(const SnackBar(content: Text('Account deleted')));
    if (context.mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('Couldn’t delete the account. Check your connection and try again.')),
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
