import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/billing.dart';
import '../../../services/plan.dart';
import '../../../services/supabase_sync.dart';
import '../../auth/account_auth.dart';
import '../../scanner/application/scan_controller.dart';
import 'account_screen.dart';

/// Account storage screen mirroring Fing's layout:
/// - Account tier (FREE / PRO)
/// - Account state (OK / Offline / Local)
/// - Networks in your account (count)
/// - Restore and Refresh buttons
/// - Local inventory management (clear inventory)
class AccountStorageScreen extends ConsumerWidget {
  const AccountStorageScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(accountEmailProvider).value;
    final plan = ref.watch(currentPlanProvider).value;
    final isPaid = plan?.isPaid ?? false;
    final usage = ref.watch(storageUsageProvider).value;
    final scanning = ref.watch(scanControllerProvider).isScanning;
    final sync = ref.watch(supabaseSyncProvider);

    final accountTier = isPaid ? 'PRO' : 'FREE';
    final accountState = email == null
        ? 'LOCAL'
        : sync.phase == SyncPhase.syncing
            ? 'SYNCING…'
            : sync.phase == SyncPhase.failed
                ? 'OFFLINE'
                : 'OK';
    final networksCount = '${usage?.networks ?? 0}';

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Account storage',
          style: PdText.headlineSm.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
          // 1. Storage Status Rows
          _StorageRow(
            icon: Icons.person_outline,
            title: 'Account',
            trailingText: accountTier,
          ),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
          _StorageRow(
            icon: Icons.check,
            title: 'Account state',
            trailingText: accountState,
            trailingColor: accountState == 'OK' ? PingDuckColors.live : PingDuckColors.inkSecondary,
          ),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
          _StorageRow(
            icon: Icons.wifi,
            title: 'Networks in your account',
            trailingText: networksCount,
          ),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
          const SizedBox(height: 20),

          // 2. Action Controls (Restore + Refresh)
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: FilledButton(
                    key: const Key('restore_storage_button'),
                    style: FilledButton.styleFrom(
                      backgroundColor: PingDuckColors.route,
                      foregroundColor: PingDuckColors.canvas,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      elevation: 0,
                    ),
                    onPressed: () => _restore(context, ref),
                    child: Text(
                      'Restore',
                      style: PdText.bodyMd.copyWith(
                        color: PingDuckColors.canvas,
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Material(
                color: PingDuckColors.surface2,
                shape: const CircleBorder(),
                clipBehavior: Clip.antiAlias,
                child: IconButton(
                  key: const Key('refresh_storage_button'),
                  tooltip: 'Refresh',
                  icon: const Icon(Icons.sync, color: PingDuckColors.route),
                  iconSize: 22,
                  onPressed: () => _refresh(context, ref),
                ),
              ),
            ],
          ),
          const SizedBox(height: 36),

          // 3. Local Inventory Details & Wipe
          Text(
            'LOCAL CACHE',
            style: PdText.labelLg.copyWith(
              color: PingDuckColors.inkSecondary,
              letterSpacing: 1.2,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: PingDuckColors.surface1,
              border: Border.all(color: PingDuckColors.partition),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Local inventory', style: PdText.headlineSm.copyWith(fontSize: 16)),
                const SizedBox(height: 4),
                Text(
                  usage != null
                      ? '${usage.devices} device${usage.devices == 1 ? '' : 's'} on ${usage.networks} network${usage.networks == 1 ? '' : 's'}'
                      : 'Loading…',
                  style: PdText.bodySm.copyWith(fontWeight: FontWeight.w600, color: PingDuckColors.ink),
                ),
                const SizedBox(height: 6),
                Text(
                  'Names, custom notes, vendor labels and latency history saved on this device.',
                  style: PdText.bodySm.copyWith(color: PingDuckColors.inkSecondary),
                ),
                const SizedBox(height: 16),
                PdButton(
                  label: 'Clear device inventory',
                  icon: Icons.delete_outline,
                  style: PdButtonStyle.destructive,
                  onPressed: scanning ? null : () => _confirmClear(context, ref),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
  }

  static Future<void> _restore(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(billingProvider).restore();
      ref.invalidate(currentPlanProvider);
      ref.invalidate(storageUsageProvider);
      ref.invalidate(supabaseSyncProvider);
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Account storage up to date.')));
    } catch (_) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(content: Text('Could not restore account storage.')));
    }
  }

  static void _refresh(BuildContext context, WidgetRef ref) {
    ref.invalidate(storageUsageProvider);
    ref.invalidate(currentPlanProvider);
    ref.invalidate(supabaseSyncProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(content: Text('Storage status refreshed.')));
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

class _StorageRow extends StatelessWidget {
  const _StorageRow({
    required this.icon,
    required this.title,
    required this.trailingText,
    this.trailingColor,
  });

  final IconData icon;
  final String title;
  final String trailingText;
  final Color? trailingColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 4),
      child: Row(
        children: [
          Icon(icon, size: 22, color: PingDuckColors.ink),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              title,
              style: PdText.bodyLg.copyWith(
                fontWeight: FontWeight.w500,
                fontSize: 16,
                color: PingDuckColors.ink,
              ),
            ),
          ),
          Text(
            trailingText,
            style: PdText.bodyMd.copyWith(
              fontWeight: FontWeight.w600,
              fontSize: 14,
              letterSpacing: 0.5,
              color: trailingColor ?? PingDuckColors.inkSecondary,
            ),
          ),
        ],
      ),
    );
  }
}
