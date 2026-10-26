import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/revenuecat_config.dart';
import '../../../core/desktop/desktop.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/billing.dart';
import '../../../services/external_links.dart';
import '../../../services/plan.dart';
import '../../../services/push_alerts.dart';
import '../../agent/application/agent_status.dart';
import '../../agent/domain/agent_unit.dart';
import '../../agent/presentation/add_unit_intro_screen.dart';
import '../../agent/presentation/this_pc_panel.dart';
import '../../auth/account_auth.dart';
import '../../auth/sign_in_screen.dart';
import '../../scanner/application/scan_controller.dart';
import '../../settings/presentation/settings_screen.dart';
import '../../shell/app_shell.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../../subscription/presentation/plan_panel.dart';
import '../../tools/presentation/tools_screen.dart';
import 'about_contacts_screen.dart';
import 'account_details_screen.dart';

/// The homelab agent's version: the account's paired agent, as its last
/// heartbeat reported it, else (desktop) the agent service on this PC.
/// Null when there is neither.
final agentVersionProvider = FutureProvider.autoDispose<String?>((ref) async {
  final agents = ref.watch(myAgentsProvider).value ?? const <PairedAgent>[];
  final paired = agents.map((a) => a.version).nonNulls.firstOrNull;
  if (paired != null) return paired;
  if (!isDesktop) return null;
  try {
    return (await ref.watch(localAgentProvider.future))?.version;
  } catch (_) {
    return null;
  }
});

/// What the local cache holds; refreshed after scans and wipes.
final storageUsageProvider = FutureProvider<({int networks, int devices})>((ref) {
  ref.watch(scanControllerProvider.select((s) => (s.lastScanAt, s.devices.length)));
  return ref.read(localStoreProvider).usage();
});

/// Account screen redesigned to mirror Fing's clean structured hierarchy:
/// Profile -> Workspace -> Your plan -> Settings -> Support,
/// adhering strictly to PingDuck's "Precision Editorial Recon" design system.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
        // 1. Top Header: Account
        Text(
          'Account',
          style: PdText.headlineLg.copyWith(fontSize: 28, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
        const SizedBox(height: 12),

        // 2. User Profile Card
        const _ProfileCard(),

        if (isDesktop) ...[
          const SizedBox(height: 14),
          const ThisPcPanel(),
        ],

        // 3. Workspace Section
        const _SectionHeader('Workspace'),
        _AccountActionRow(
          icon: Icons.cloud_outlined,
          title: 'Account storage',
          subtitle: switch (ref.watch(storageUsageProvider)) {
            AsyncData(:final value) =>
              '${value.devices} device${value.devices == 1 ? '' : 's'} on ${value.networks} network${value.networks == 1 ? '' : 's'}',
            _ => null,
          },
          onTap: () => _showStorageSheet(context, ref),
        ),
        _AccountActionRow(
          icon: Icons.mail_outline,
          title: 'Notifications',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),
        switch (ref.watch(myAgentsProvider).value?.length ?? 0) {
          0 => _AccountActionRow(
              icon: Icons.connected_tv_outlined,
              title: 'Add monitoring unit',
              onTap: () => openAddMonitoringUnit(context),
            ),
          final n => _AccountActionRow(
              icon: Icons.dns_outlined,
              title: 'Monitoring units',
              subtitle: '$n agent${n == 1 ? '' : 's'} paired',
              onTap: () {
                ref.read(appTabProvider.notifier).go(AppTab.tools);
                ref.read(activeToolProvider.notifier).open(Tool.agent);
              },
            ),
        },

        // 4. Your plan Section
        const _SectionHeader('Your plan'),
        const _PlanPromoCard(),
        const SizedBox(height: 6),
        _AccountActionRow(
          icon: Icons.sync,
          title: 'Restore',
          onTap: () => _restorePurchases(context, ref),
        ),

        // 5. Settings Section
        const _SectionHeader('Settings'),
        _AccountActionRow(
          icon: Icons.info_outline,
          title: 'About us & this App',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const AboutContactsScreen()),
          ),
        ),
        _AccountActionRow(
          icon: Icons.settings_outlined,
          title: 'App settings',
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute<void>(builder: (_) => const SettingsScreen()),
          ),
        ),

        // 6. Support Section
        const _SectionHeader('Support'),
        _AccountActionRow(
          icon: Icons.chat_bubble_outline,
          title: 'Knowledge base',
          onTap: () => openExternalUrl(websiteUrl),
        ),
        _AccountActionRow(
          icon: Icons.ondemand_video_outlined,
          title: 'YouTube tutorials',
          onTap: () => openExternalUrl('https://www.youtube.com/@BigDuckNetworks'),
        ),
        if (ref.watch(accountEmailProvider).value != null) ...[
          const SizedBox(height: 20),
          PdButton(
            label: 'Sign out',
            icon: Icons.logout,
            style: PdButtonStyle.destructive,
            onPressed: () => _signOut(context, ref),
          ),
        ],
        const SizedBox(height: 32),
        ],
      ),
    );
  }

  static Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final alerts = ref.read(pushAlertsProvider);
    if (await alerts.isEnabled()) await alerts.disable().catchError((_) {});
    await ref.read(accountAuthProvider).signOut();
    ref.invalidate(alertsEnabledProvider);
  }

  static Future<void> _restorePurchases(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(const SnackBar(content: Text('Checking Google Play for purchases…')));
    try {
      await ref.read(billingProvider).restore();
      ref.invalidate(currentPlanProvider);
      ref.invalidate(subscriptionDetailsProvider);
      messenger.showSnackBar(const SnackBar(content: Text('Purchases restored.')));
    } catch (_) {
      messenger.showSnackBar(const SnackBar(content: Text('Could not restore purchases.')));
    }
  }

  static void _showStorageSheet(BuildContext context, WidgetRef ref) {
    final usage = ref.read(storageUsageProvider).value;
    final scanning = ref.read(scanControllerProvider).isScanning;

    showModalBottomSheet<void>(
      context: context,
      backgroundColor: PingDuckColors.canvas,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(12))),
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
                  Text('ACCOUNT STORAGE', style: PdText.labelLg),
                  IconButton(
                    icon: const Icon(Icons.close, size: 20),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PdField(
                label: 'Local Inventory',
                value: usage != null
                    ? '${usage.devices} device${usage.devices == 1 ? '' : 's'} on ${usage.networks} network${usage.networks == 1 ? '' : 's'}'
                    : 'Loading…',
                sub: 'Names, custom notes, vendor labels and latency history included.',
              ),
              const SizedBox(height: 20),
              PdButton(
                label: 'Clear device inventory',
                icon: Icons.delete_outline,
                style: PdButtonStyle.destructive,
                onPressed: scanning
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        _confirmClear(context, ref);
                      },
              ),
            ],
          ),
        ),
      ),
    );
  }

  static Future<void> _confirmClear(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('CLEAR INVENTORY?', style: PdText.labelLg),
        content: Text(
          'Removes every remembered network and device, including your names and notes. The next scan starts fresh.',
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

/// Profile row modeled directly on Fing's top profile tile.
class _ProfileCard extends ConsumerWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(accountEmailProvider).value;
    final signedIn = email != null;
    final customName = ref.watch(userDisplayNameProvider).value;
    final displayName = signedIn
        ? (customName ?? (email.split('@').firstOrNull ?? 'User'))
        : 'Not signed in';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () {
            if (!signedIn) {
              Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const SignInScreen()),
              );
            } else {
              Navigator.of(context).push<void>(
                MaterialPageRoute(builder: (_) => const AccountDetailsScreen()),
              );
            }
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Row(
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PingDuckColors.surface2,
                    border: Border.all(color: PingDuckColors.partition),
                  ),
                  child: Center(
                    child: Icon(
                      signedIn ? Icons.person : Icons.person_outline,
                      size: 28,
                      color: signedIn ? PingDuckColors.ink : PingDuckColors.inkMuted,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              displayName,
                              style: PdText.headlineSm.copyWith(fontWeight: FontWeight.w600),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (signedIn) ...[
                            const SizedBox(width: 8),
                            const PdChip('SIGNED IN', tone: PdTone.live),
                          ],
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        signedIn ? email : 'Sign in to sync networks & alerts',
                        style: PdText.bodySm.copyWith(
                          color: signedIn ? PingDuckColors.inkSecondary : PingDuckColors.inkMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, size: 22, color: PingDuckColors.inkSecondary),
              ],
            ),
          ),
        ),
        if (!signedIn) ...[
          const SizedBox(height: 10),
          PdButton(
            label: 'Sign in or create account',
            icon: Icons.login,
            style: PdButtonStyle.primary,
            onPressed: () => Navigator.of(context).push<bool>(
              MaterialPageRoute(builder: (_) => const SignInScreen()),
            ),
          ),
        ],
      ],
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
      padding: const EdgeInsets.only(top: 22, bottom: 6),
      child: Text(
        title,
        style: PdText.headlineSm.copyWith(
          fontSize: 18,
          fontWeight: FontWeight.w700,
          color: PingDuckColors.ink,
        ),
      ),
    );
  }
}

/// Single action row with leading icon, title, optional subtitle, and chevron.
class _AccountActionRow extends StatelessWidget {
  const _AccountActionRow({
    required this.icon,
    required this.title,
    this.subtitle,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 2),
        child: Row(
          children: [
            Icon(icon, size: 22, color: PingDuckColors.ink),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: PdText.bodyLg.copyWith(
                      fontWeight: FontWeight.w500,
                      color: PingDuckColors.ink,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 2),
                    Text(subtitle!, style: PdText.bodySm),
                  ],
                ],
              ),
            ),
            const Icon(Icons.chevron_right, size: 20, color: PingDuckColors.inkSecondary),
          ],
        ),
      ),
    );
  }
}

/// Prominent plan banner card mirroring Fing's promo/subscription card
/// using PingDuck's design system tokens and buttons.
class _PlanPromoCard extends ConsumerWidget {
  const _PlanPromoCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(currentPlanProvider).value;
    final details = ref.watch(subscriptionDetailsProvider).value;
    final isPaid = plan?.isPaid ?? false;

    return Container(
      decoration: BoxDecoration(
        color: PingDuckColors.surface1,
        border: Border.all(
          color: isPaid ? PingDuckColors.liveBorder : PingDuckColors.route,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  isPaid ? 'PingDuck Pro is active' : 'Try Pro for 24/7 monitoring!',
                  style: PdText.headlineSm.copyWith(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
              if (isPaid)
                const PdChip('PRO', tone: PdTone.live)
              else
                const PdChip('FREE', tone: PdTone.pending),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            isPaid
                ? (details?.expiresAt != null
                    ? 'Renews ${MaterialLocalizations.of(context).formatMediumDate(details!.expiresAt!)}.'
                    : 'Unlimited network sweeps and automated background monitoring.')
                : '3 scans a day from your phone. Get automated monitoring, advanced protection, and real-time network intrusion alerts.',
            style: PdText.bodySm,
          ),
          const SizedBox(height: 14),
          if (!isPaid)
            PdButton(
              key: const Key('go_premium'),
              label: 'UPGRADE TO PRO',
              icon: Icons.workspace_premium_outlined,
              style: PdButtonStyle.primary,
              onPressed: () => openPaywall(context, ref),
            )
          else
            PdButton(
              key: const Key('manage_subscription'),
              label: 'MANAGE SUBSCRIPTION',
              icon: Icons.open_in_new,
              onPressed: () => openExternalUrl(details?.manageUrl ?? playSubscriptionsUrl),
            ),
        ],
      ),
    );
  }
}
