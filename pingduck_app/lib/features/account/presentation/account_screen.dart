import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/app_version.dart';
import '../../../core/desktop/desktop.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
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
import '../../subscription/presentation/plan_panel.dart';
import '../../tools/presentation/tools_screen.dart';

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

/// Account tab: who is signed in, settings, local data and about. Signing in
/// gives the install an account to sync and pair agents with later; scans and
/// the inventory stay on this device either way.
class AccountScreen extends ConsumerWidget {
  const AccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final usage = ref.watch(storageUsageProvider);
    final scanning = ref.watch(scanControllerProvider.select((s) => s.isScanning));

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PdSectionHeader(title: 'Account', icon: Icons.person_outline),
        const SizedBox(height: 16),
        const _IdentityPanel(),
        const SizedBox(height: 16),
        const PlanPanel(),
        const SizedBox(height: 16),
        if (isDesktop) ...[const ThisPcPanel(), const SizedBox(height: 16)],
        PdPanel(
          title: 'Monitoring',
          icon: Icons.dns_outlined,
          child: switch (ref.watch(myAgentsProvider).value?.length ?? 0) {
            0 => _NavRow(
              icon: Icons.add,
              title: 'Add monitoring unit',
              subtitle: 'Run the agent on an always-on box',
              onTap: () => openAddMonitoringUnit(context),
            ),
            final n => _NavRow(
              icon: Icons.dns_outlined,
              title: 'Monitoring units',
              subtitle: '$n agent${n == 1 ? '' : 's'} paired',
              onTap: () {
                ref.read(appTabProvider.notifier).go(AppTab.tools);
                ref.read(activeToolProvider.notifier).open(Tool.agent);
              },
            ),
          },
        ),
        const SizedBox(height: 16),
        PdPanel(
          title: 'Settings',
          icon: Icons.tune_outlined,
          child: _NavRow(
            icon: Icons.tune_outlined,
            title: 'App settings',
            subtitle: 'Reply timeout, auto-scan, cloud sync and alerts',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
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

/// Signed-in email with sign-out, or the way to sign in. Until sign-in,
/// the install runs on an anonymous account that only counts scans.
class _IdentityPanel extends ConsumerWidget {
  const _IdentityPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(accountEmailProvider).value;
    return PdPanel(
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
                    Text(email ?? 'Not signed in', style: PdText.headlineSm, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Text(email == null ? 'No account needed.' : 'Signed in with email', style: PdText.bodySm),
                  ],
                ),
              ),
              email == null ? const PdChip('LOCAL') : const PdChip('SIGNED IN', tone: PdTone.live),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            email == null
                ? 'Your devices and notes stay on this phone either way. An account keeps your plan on a new '
                      'phone, and later syncs your inventory and connects the Homelab Agent for intrusion alerts.'
                : 'Your inventory stays on this device until cloud sync arrives.',
            style: PdText.bodySm,
          ),
          const SizedBox(height: 12),
          email == null
              ? PdButton(
                  label: 'Sign in or create account',
                  icon: Icons.login,
                  style: PdButtonStyle.primary,
                  // SignInScreen shows its own toast on success.
                  onPressed: () =>
                      Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen())),
                )
              : PdButton(
                  label: 'Sign out',
                  icon: Icons.logout,
                  onPressed: () async {
                    // Alerts for this account must stop reaching this phone.
                    final alerts = ref.read(pushAlertsProvider);
                    if (await alerts.isEnabled()) await alerts.disable().catchError((_) {});
                    await ref.read(accountAuthProvider).signOut();
                    ref.invalidate(alertsEnabledProvider);
                  },
                ),
        ],
      ),
    );
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
    final agent = ref.watch(agentVersionProvider).value;
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
          const SizedBox(height: 12),
          const Wrap(spacing: 8, runSpacing: 6, children: [PdChip('Made on Long Island')]),
          const SizedBox(height: 16),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: PdField(
                    label: 'Version',
                    value: AppVersion.display,
                    sub: '${AppVersion.gitCommit} · ${AppVersion.buildDate}',
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PdField(label: 'Agent version', value: agent ?? '—'),
                ),
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
                  'No data leaves this device unless you enable cloud sync.',
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
                  applicationVersion: AppVersion.display,
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

/// A tappable row inside a panel: icon tile, title and subtitle, chevron.
class _NavRow extends StatelessWidget {
  const _NavRow({required this.icon, required this.title, required this.subtitle, required this.onTap});
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: title,
      child: InkWell(
        onTap: onTap,
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
                child: Icon(icon, size: 20, color: PingDuckColors.ink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: PdText.headlineSm),
                    const SizedBox(height: 2),
                    Text(subtitle, style: PdText.bodySm),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, size: 20, color: PingDuckColors.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
