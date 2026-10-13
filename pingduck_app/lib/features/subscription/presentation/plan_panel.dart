import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/constants/revenuecat_config.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/billing.dart';
import '../../../services/external_links.dart';
import '../../../services/plan.dart';
import '../../auth/account_auth.dart';
import 'paywall_screen.dart';

/// What Google Play says about the subscription, refetched whenever the plan
/// changes. Display only; [currentPlanProvider] decides what is unlocked.
final subscriptionDetailsProvider = FutureProvider<SubscriptionDetails?>((ref) async {
  ref.watch(currentPlanProvider);
  try {
    return await ref.read(billingProvider).details();
  } catch (_) {
    return null;
  }
});

/// Account tab: the plan, and the ways to upgrade, restore or manage it.
class PlanPanel extends ConsumerWidget {
  const PlanPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final plan = ref.watch(currentPlanProvider).value;
    final details = ref.watch(subscriptionDetailsProvider).value;
    final signedIn = ref.watch(accountEmailProvider).value != null;

    return PdPanel(
      title: 'Plan',
      icon: Icons.workspace_premium_outlined,
      trailing: plan == null
          ? null
          : plan.isPaid
          ? PdChip(plan.name.toUpperCase(), tone: PdTone.live)
          : const PdChip('FREE'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: switch (plan) {
          null => [Text('Checking your plan…', style: PdText.bodySm)],
          Plan(isPaid: false) => [
            Text(
              '${plan.dailyScanLimit ?? Plan.free.dailyScanLimit} scans a day from your phone. '
              'No monitoring or alerts.',
              style: PdText.bodySm,
            ),
            const SizedBox(height: 12),
            if (billingSupported) ...[
              PdButton(
                key: const Key('go_premium'),
                label: 'Go Premium',
                icon: Icons.workspace_premium_outlined,
                style: PdButtonStyle.primary,
                onPressed: () => openPaywall(context, ref),
              ),
              if (signedIn) _RestoreButton(ref: ref),
            ] else
              Text(
                'Subscriptions are available in the Android app for now.',
                style: PdText.bodySm.copyWith(color: PingDuckColors.inkMuted),
              ),
          ],
          _ when details != null && details.active => [
            Text(
              _storeLine(context, details),
              style: PdText.bodySm.copyWith(color: details.billingIssue ? PingDuckColors.critical : null),
            ),
            const SizedBox(height: 12),
            PdButton(
              key: const Key('manage_subscription'),
              label: 'Manage subscription',
              icon: Icons.open_in_new,
              onPressed: () => _manage(context, details.manageUrl ?? playSubscriptionsUrl),
            ),
            _RestoreButton(ref: ref),
          ],
          // A manual grant, or a phone that can't see the store.
          _ => [Text('${plan.name} is active on this account.', style: PdText.bodySm)],
        },
      ),
    );
  }

  static String _storeLine(BuildContext context, SubscriptionDetails d) {
    final date = d.expiresAt == null ? null : MaterialLocalizations.of(context).formatMediumDate(d.expiresAt!);
    if (d.billingIssue) return 'Payment problem · Fix it in Google Play to keep Premium.';
    if (date == null) return 'Premium is active.';
    if (d.inTrial) return d.willRenew ? 'Free trial · Ends $date' : 'Free trial · Cancelled, Premium until $date';
    return d.willRenew ? 'Renews $date' : 'Cancelled · Premium until $date';
  }

  static Future<void> _manage(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.of(context);
    if (!await openExternalUrl(url)) {
      messenger.showSnackBar(const SnackBar(content: Text('Couldn’t open Google Play.')));
    }
  }
}

class _RestoreButton extends StatelessWidget {
  const _RestoreButton({required this.ref});
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) => Align(
    alignment: Alignment.centerLeft,
    child: TextButton(
      key: const Key('restore_purchases'),
      onPressed: () => restorePurchases(context, ref),
      child: const Text('RESTORE PURCHASES'),
    ),
  );
}
