import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/plan.dart';
import '../../../services/push_alerts.dart';
import '../../auth/account_auth.dart';
import '../../scanner/application/scan_controller.dart';
import '../../settings/presentation/settings_screen.dart';

const userDisplayNameKey = 'userCustomDisplayName';

final userDisplayNameProvider = FutureProvider<String?>((ref) async {
  final custom = await ref.read(localStoreProvider).setting(userDisplayNameKey);
  if (custom != null && custom.trim().isNotEmpty) return custom.trim();
  final email = ref.watch(accountEmailProvider).value;
  if (email == null) return null;
  return email.split('@').firstOrNull;
});

/// Account details screen mirroring Fing's profile details screen:
/// Large centered avatar, user name, email, plan status, and action rows
/// (Edit profile, Reset password, Delete account, Sign out).
class AccountDetailsScreen extends ConsumerWidget {
  const AccountDetailsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final email = ref.watch(accountEmailProvider).value;
    final displayName = ref.watch(userDisplayNameProvider).value ??
        (email?.split('@').firstOrNull ?? 'User');
    final plan = ref.watch(currentPlanProvider).value;
    final isPaid = plan?.isPaid ?? false;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Account details',
          style: PdText.headlineSm.copyWith(fontWeight: FontWeight.w600, fontSize: 18),
        ),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
        children: [
          // 1. Centered Profile Header
          Center(
            child: Column(
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: PingDuckColors.surface2,
                    border: Border.all(color: PingDuckColors.partition, width: 2),
                  ),
                  child: const Center(
                    child: Icon(Icons.person, size: 52, color: PingDuckColors.ink),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  displayName,
                  style: PdText.headlineLg.copyWith(fontSize: 22, fontWeight: FontWeight.w700),
                  textAlign: TextAlign.center,
                ),
                if (email != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    email,
                    style: PdText.bodyMd.copyWith(color: PingDuckColors.inkSecondary),
                    textAlign: TextAlign.center,
                  ),
                ],
                const SizedBox(height: 8),
                PdChip(
                  isPaid ? 'PRO SUBSCRIBER' : 'FREE PLAN',
                  tone: isPaid ? PdTone.live : PdTone.neutral,
                ),
              ],
            ),
          ),
          const SizedBox(height: 28),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),

          // 2. Action Rows
          _ActionRow(
            icon: Icons.edit_outlined,
            title: 'Edit profile',
            onTap: () => _editProfile(context, ref, displayName),
          ),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
          _ActionRow(
            icon: Icons.lock_outline,
            title: 'Reset password',
            onTap: () => _resetPassword(context, ref, email),
          ),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
          _ActionRow(
            icon: Icons.delete_outline,
            title: 'Delete account',
            onTap: () => confirmDeleteAccount(context, ref),
          ),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
          _ActionRow(
            icon: Icons.logout,
            title: 'Sign out',
            onTap: () => _signOut(context, ref),
          ),
          const Divider(height: 1, thickness: 1, color: PingDuckColors.hairline),
        ],
      ),
    );
  }

  static Future<void> _editProfile(BuildContext context, WidgetRef ref, String currentName) async {
    final controller = TextEditingController(text: currentName);
    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('EDIT PROFILE', style: PdText.labelLg),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Display Name',
            hintText: 'Enter your name',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CANCEL'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: Text('SAVE', style: PdText.labelLg.copyWith(color: PingDuckColors.route)),
          ),
        ],
      ),
    );
    if (newName != null && newName.isNotEmpty) {
      await ref.read(localStoreProvider).setSetting(userDisplayNameKey, newName);
      ref.invalidate(userDisplayNameProvider);
    }
  }

  static Future<void> _resetPassword(BuildContext context, WidgetRef ref, String? email) async {
    if (email == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('RESET PASSWORD?', style: PdText.labelLg),
        content: Text(
          'Send a password reset link to $email?',
          style: PdText.bodyMd,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('SEND LINK', style: PdText.labelLg.copyWith(color: PingDuckColors.route)),
          ),
        ],
      ),
    );
    if (confirm != true) return;
    try {
      await ref.read(accountAuthProvider).sendPasswordReset(email);
      messenger.showSnackBar(SnackBar(content: Text('Password reset link sent to $email')));
    } catch (_) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Could not send reset link. Try again later.')),
      );
    }
  }

  static Future<void> _signOut(BuildContext context, WidgetRef ref) async {
    final alerts = ref.read(pushAlertsProvider);
    if (await alerts.isEnabled()) await alerts.disable().catchError((_) {});
    await ref.read(accountAuthProvider).signOut();
    ref.invalidate(alertsEnabledProvider);
    if (context.mounted) {
      Navigator.of(context).pop();
    }
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.icon,
    required this.title,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(4),
      child: Padding(
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
            const Icon(Icons.chevron_right, size: 20, color: PingDuckColors.inkSecondary),
          ],
        ),
      ),
    );
  }
}
