import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/revenuecat_config.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../services/billing.dart';
import '../../../services/external_links.dart';
import '../../../services/plan.dart';
import '../../../services/push_alerts.dart';
import '../../../services/scan_quota.dart';
import '../../../services/supabase_sync.dart';
import '../../agent/application/agent_status.dart';
import '../../account/presentation/account_details_screen.dart';
import '../../agent/domain/agent_unit.dart';
import '../../agent/presentation/add_unit_intro_screen.dart';
import '../../auth/account_auth.dart';
import '../../scanner/application/scan_controller.dart';
import '../../shell/app_shell.dart';
import '../../subscription/presentation/paywall_screen.dart';
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

/// Whether the account's plan is paid, from the server (`my_plan()`).
final isPremiumProvider = FutureProvider<bool>((ref) async => (await ref.watch(currentPlanProvider.future)).isPaid);

final cloudSyncEnabledProvider = FutureProvider<bool>(
  (ref) async => await ref.read(localStoreProvider).setting(cloudSyncKey) != '0',
);

/// App settings redesigned to match Fing's clean list layout with switches,
/// badges, and hairline dividers, adhering to PingDuck's design system.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key, this.initialIndex = 0});

  final int initialIndex;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(appThemeModeProvider);
    if (initialIndex == 1) {
      return const AccountDetailsScreen();
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('App settings'),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: const _AppSettingsTab(),
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

    final agents = ref.watch(myAgentsProvider).value ?? const <PairedAgent>[];
    final hasAgent = agents.isNotEmpty;
    final syncOn = ref.watch(cloudSyncEnabledProvider).value ?? true;
    final sync = ref.watch(supabaseSyncProvider);

    final alertsOn = ref.watch(alertsEnabledProvider).value ?? false;
    final alertsBlocker = !hasAgent
        ? 'Needs a monitoring unit'
        : !isPremium
            ? 'Premium plan required'
            : !alertsSupported
                ? 'Android only for now'
                : null;
    final themeMode = ref.watch(appThemeModeProvider);

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      children: [
        // APPEARANCE Section
        const _SectionHeader('APPEARANCE'),
        _SettingRow(
          title: 'Theme',
          subtitle: switch (themeMode) {
            ThemeMode.light => 'Light',
            ThemeMode.dark => 'Dark (pitch-black AMOLED)',
            ThemeMode.system => 'System default',
          },
          trailing: _PillBadge(
            label: switch (themeMode) {
              ThemeMode.light => 'Light',
              ThemeMode.dark => 'Dark',
              ThemeMode.system => 'System',
            },
            onTap: () => _showThemeSheet(context, ref, themeMode),
          ),
          onTap: () => _showThemeSheet(context, ref, themeMode),
        ),
        Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),

        // SCANNING Section
        const _SectionHeader('SCANNING'),
        _SettingRow(
          title: 'Auto-scan on launch',
          subtitle: isPremium
              ? 'Automatically start a network scan when the app opens.'
              : 'Automatically start a network scan when the app opens. On Free, at most once every 30 minutes.',
          trailing: Switch(
            key: const Key('auto_scan_switch'),
            value: autoScan,
            activeTrackColor: PingDuckColors.route,
            onChanged: (enabled) async {
              await setAutoScanOnLaunch(ref.read(localStoreProvider), enabled);
              ref.invalidate(autoScanOnLaunchProvider);
            },
          ),
        ),
        Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
        _SettingRow(
          title: 'Reply timeout',
          subtitle: 'How long to wait for slow devices during network discovery.',
          trailing: _PillBadge(
            label: '${timeout}s',
            onTap: () => _showTimeoutSheet(context, ref, timeout),
          ),
        ),
        Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),

        // CLOUD & ALERTS Section
        const _SectionHeader('CLOUD & ALERTS'),
        _SettingRow(
          title: 'Homelab Agent',
          subtitle: hasAgent ? _agentLine(agents, DateTime.now()) : 'Not set up · Add a monitoring unit',
          trailing: Icon(Icons.chevron_right, size: 22, color: PingDuckColors.inkMuted),
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
        Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
        _SettingRow(
          title: 'Cloud sync',
          subtitle: !hasAgent ? 'Needs a monitoring unit' : _syncLine(syncOn, sync, DateTime.now()),
          trailing: Switch(
            key: const Key('cloud_sync_switch'),
            value: hasAgent && syncOn,
            activeTrackColor: PingDuckColors.route,
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
        Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
        _SettingRow(
          title: 'New-device alerts',
          subtitle: alertsBlocker ?? (alertsOn ? 'On · A notification when a device joins' : 'Off'),
          onTap: hasAgent && !isPremium ? () => openPaywall(context, ref) : null,
          trailing: Switch(
            key: const Key('alerts_switch'),
            value: alertsBlocker == null && alertsOn,
            activeTrackColor: PingDuckColors.route,
            onChanged: alertsBlocker == null ? (on) => _setAlerts(context, ref, on) : null,
          ),
        ),
        if (hasAgent) ...[
          Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
          _SettingRow(
            title: 'Mark devices as known',
            subtitle: 'Current devices won’t trigger alerts; only newly joined devices will.',
            trailing: TextButton(
              key: const Key('mark_all_known'),
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
              child: Text(
                'MARK ALL KNOWN',
                style: PdText.labelMd.copyWith(color: PingDuckColors.route),
              ),
            ),
          ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }

  static Future<void> _setAlerts(BuildContext context, WidgetRef ref, bool on) async {
    final messenger = ScaffoldMessenger.of(context);
    final alerts = ref.read(pushAlertsProvider);
    try {
      await (on ? alerts.enable() : alerts.disable());
    } on NotificationsDeniedException {
      messenger.showSnackBar(
        const SnackBar(content: Text('Notifications are off for PingDuck. Turn them on in Android settings.')),
      );
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn’t reach PingDuck’s servers. Try again.')));
    }
    ref.invalidate(alertsEnabledProvider);
  }

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

  static void _showTimeoutSheet(BuildContext context, WidgetRef ref, int current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PingDuckColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('REPLY TIMEOUT', style: PdText.labelLg),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'How long to wait for slow devices during network discovery.',
                style: PdText.bodySm,
              ),
              const SizedBox(height: 16),
              for (final s in scanTimeoutChoices) ...[
                InkWell(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await ref.read(localStoreProvider).setSetting(scanTimeoutKey, '$s');
                    ref.invalidate(scanTimeoutProvider);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Row(
                      children: [
                        Text(
                          '${s}s',
                          style: PdText.headlineSm.copyWith(
                            color: s == current ? PingDuckColors.route : PingDuckColors.ink,
                            fontWeight: s == current ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            switch (s) {
                              1 => 'Fastest · Quiet networks',
                              3 => 'Default · Balanced discovery',
                              5 => 'Thorough · Busy Wi-Fi networks',
                              _ => 'Deep scan · High-latency hosts',
                            },
                            style: PdText.bodySm.copyWith(
                              color: s == current ? PingDuckColors.route : PingDuckColors.inkSecondary,
                            ),
                          ),
                        ),
                        if (s == current)
                          const Icon(Icons.check, size: 20, color: PingDuckColors.route),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
              ],
            ],
          ),
        ),
      ),
    );
  }

  static void _showThemeSheet(BuildContext context, WidgetRef ref, ThemeMode current) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PingDuckColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('THEME', style: PdText.labelLg),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                'Choose how PingDuck looks on your device.',
                style: PdText.bodySm,
              ),
              const SizedBox(height: 16),
              for (final mode in [ThemeMode.system, ThemeMode.dark, ThemeMode.light]) ...[
                InkWell(
                  onTap: () async {
                    Navigator.of(context).pop();
                    await setAppThemeMode(ref, mode);
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            switch (mode) {
                              ThemeMode.system => 'System default',
                              ThemeMode.dark => 'Dark (pitch-black AMOLED)',
                              ThemeMode.light => 'Light',
                            },
                            style: PdText.headlineSm.copyWith(
                              color: mode == current ? PingDuckColors.route : PingDuckColors.ink,
                              fontWeight: mode == current ? FontWeight.w700 : FontWeight.w500,
                              fontSize: 16,
                            ),
                          ),
                        ),
                        if (mode == current)
                          const Icon(Icons.check, size: 20, color: PingDuckColors.route),
                      ],
                    ),
                  ),
                ),
                Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
              ],
            ],
          ),
        ),
      ),
    );
  }
}



/// Category section header.
class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);
  final String title;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Text(
        title,
        style: PdText.labelLg.copyWith(
          color: PingDuckColors.inkSecondary,
          letterSpacing: 1.2,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// Single setting row with title, subtitle, and trailing switch/badge/chevron.
class _SettingRow extends StatelessWidget {
  const _SettingRow({
    required this.title,
    required this.subtitle,
    this.trailing,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: PdText.bodyLg.copyWith(
                    fontWeight: FontWeight.w600,
                    fontSize: 16,
                    color: PingDuckColors.ink,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: PdText.bodySm.copyWith(
                    color: PingDuckColors.inkSecondary,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
          if (trailing != null) ...[
            const SizedBox(width: 16),
            trailing!,
          ],
        ],
      ),
    );

    if (onTap != null) {
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(4),
        child: row,
      );
    }
    return row;
  }
}

/// Pill badge for selector items (e.g. timeout duration).
class _PillBadge extends StatelessWidget {
  const _PillBadge({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        decoration: BoxDecoration(
          color: PingDuckColors.routeFill,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: PingDuckColors.routeBorder),
        ),
        child: Text(
          label,
          style: PdText.bodySm.copyWith(
            color: PingDuckColors.route,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }
}

/// Apple requires in-app deletion for any app that creates accounts.
/// Deleting doesn't cancel store billing, so a renewing subscription gets a
/// warning and a way to Google Play's subscription page.
Future<void> confirmDeleteAccount(BuildContext context, WidgetRef ref) async {
  SubscriptionDetails? sub;
  try {
    sub = await ref.read(billingProvider).details();
  } catch (_) {}
  if (!context.mounted) return;
  final billing = sub != null && sub.active && sub.willRenew;
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('DELETE ACCOUNT?', style: PdText.labelLg),
      // Scrolls on small phones, where the warning makes it taller.
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Permanently deletes your account and the email, plan and scan history stored with it. This can’t '
              'be undone. Devices and notes on this phone stay until you clear them. Subscriptions are billed by '
              'Apple or Google, so cancel any in the store first.',
              style: PdText.bodyMd,
            ),
            if (billing) ...[
              const SizedBox(height: 12),
              Text(
                'Your Premium subscription keeps billing until you cancel it in Google Play. Deleting your account '
                'doesn’t cancel it.',
                key: const Key('delete_subscription_warning'),
                style: PdText.bodyMd.copyWith(color: PingDuckColors.critical),
              ),
            ],
          ],
        ),
      ),
      actions: [
        if (billing)
          TextButton(
            onPressed: () => openExternalUrl(sub?.manageUrl ?? playSubscriptionsUrl),
            child: const Text('OPEN GOOGLE PLAY'),
          ),
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
