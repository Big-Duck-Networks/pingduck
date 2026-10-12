import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/scan_quota.dart';
import '../../../services/supabase_sync.dart';
import '../../agent/application/agent_status.dart';
import '../../agent/domain/agent_unit.dart';
import '../../agent/presentation/add_unit_intro_screen.dart';
import '../../auth/account_auth.dart';
import '../../scanner/application/scan_controller.dart';
import '../../shell/app_shell.dart';
import '../../tools/presentation/tools_screen.dart';

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

final cloudSyncEnabledProvider = FutureProvider<bool>(
  (ref) async => await ref.read(localStoreProvider).setting(cloudSyncKey) != '0',
);

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
                    // Premium comes from the server's plan, never from this switch.
                    onChanged: isPremium
                        ? (enabled) async {
                            await setAutoScanOnLaunch(ref.read(localStoreProvider), enabled);
                            ref.invalidate(autoScanOnLaunchProvider);
                          }
                        : null,
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        const _CloudPanel(),
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

/// Cloud & alerts: the account's agent, cloud sync and new-device alerts.
class _CloudPanel extends ConsumerWidget {
  const _CloudPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(myAgentsProvider).value ?? const <PairedAgent>[];
    final hasAgent = agents.isNotEmpty;
    final syncOn = ref.watch(cloudSyncEnabledProvider).value ?? true;
    final sync = ref.watch(supabaseSyncProvider);
    final isPremium = ref.watch(isPremiumProvider).value ?? false;

    final alertsBlocker = !hasAgent
        ? 'Needs a monitoring unit'
        : !isPremium
        ? 'Premium plan required'
        : defaultTargetPlatform != TargetPlatform.android
        ? 'Android only for now'
        : 'Coming soon';

    return PdPanel(
      title: 'Cloud & alerts',
      icon: Icons.cloud_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CloudRow(
            icon: Icons.memory,
            title: 'Homelab Agent',
            sub: hasAgent ? _agentLine(agents, DateTime.now()) : 'Not set up · Add a monitoring unit',
            trailing: const Icon(Icons.chevron_right, color: PingDuckColors.inkMuted),
            onTap: () {
              if (!hasAgent) {
                openAddMonitoringUnit(context);
                return;
              }
              Navigator.of(context).popUntil((r) => r.isFirst);
              ref.read(appTabProvider.notifier).go(AppTab.tools);
              ref.read(activeToolProvider.notifier).open(Tool.agent);
            },
          ),
          _CloudRow(
            icon: Icons.sync,
            title: 'Cloud sync',
            sub: !hasAgent ? 'Needs a monitoring unit' : _syncLine(syncOn, sync, DateTime.now()),
            trailing: Switch(
              key: const Key('cloud_sync_switch'),
              value: hasAgent && syncOn,
              onChanged: hasAgent
                  ? (on) async {
                      await ref.read(localStoreProvider).setSetting(cloudSyncKey, on ? '1' : '0');
                      ref.invalidate(cloudSyncEnabledProvider);
                      final s = ref.read(supabaseSyncProvider.notifier);
                      await (on ? s.start() : s.stop());
                    }
                  : null,
            ),
          ),
          _CloudRow(
            icon: Icons.notifications_outlined,
            title: 'New-device alerts',
            sub: alertsBlocker,
            trailing: const Switch(key: Key('alerts_switch'), value: false, onChanged: null),
          ),
          if (hasAgent)
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: const Key('mark_all_known'),
                icon: const Icon(Icons.verified_outlined, size: 18),
                label: const Text('Mark all current devices as known'),
                onPressed: () async {
                  final messenger = ScaffoldMessenger.of(context);
                  try {
                    await ref.read(supabaseSyncProvider.notifier).markAllKnown();
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Current devices marked as known. Only new ones will alert.')),
                    );
                  } catch (_) {
                    messenger.showSnackBar(
                      const SnackBar(content: Text('Couldn’t reach PingDuck’s servers. Try again.')),
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }

  /// "homelab · Online · v0.3.1", plus how many more agents there are.
  static String _agentLine(List<PairedAgent> agents, DateTime now) {
    final a = agents.first;
    final status = a.isOnline(now) ? 'Online' : 'Last seen ${_ago(a.lastSeenAt, now)}';
    final more = agents.length > 1 ? ' · +${agents.length - 1} more' : '';
    return [a.name, status, if (a.version != null) 'v${a.version}'].join(' · ') + more;
  }

  static String _syncLine(bool on, SyncStatus s, DateTime now) {
    if (!on) return 'Off · Agent devices stay on the server';
    return switch (s.phase) {
      SyncPhase.syncing => 'Syncing…',
      SyncPhase.failed => 'Couldn’t sync. Retries when the app reopens.',
      SyncPhase.live when s.lastSyncedAt != null => 'Live · Synced ${_ago(s.lastSyncedAt, now)}',
      _ => 'Agent devices with MACs and vendors',
    };
  }

  static String _ago(DateTime? t, DateTime now) {
    if (t == null) return 'never';
    final d = now.difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }
}

class _CloudRow extends StatelessWidget {
  const _CloudRow({required this.icon, required this.title, required this.sub, this.trailing, this.onTap});
  final IconData icon;
  final String title;
  final String sub;
  final Widget? trailing;
  final VoidCallback? onTap;

  // PdPanel paints a background, so the tap ripple needs its own Material.
  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: ListTile(
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: PingDuckColors.inkSecondary),
          title: Text(title, style: PdText.bodyMd),
          subtitle: Text(sub, style: PdText.bodySm),
          trailing: trailing,
          onTap: onTap,
        ),
      );
}
