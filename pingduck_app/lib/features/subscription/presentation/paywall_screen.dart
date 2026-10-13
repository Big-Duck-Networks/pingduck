import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/billing.dart';
import '../../../services/external_links.dart';
import '../../../services/plan.dart';
import '../../auth/account_auth.dart';
import '../../auth/sign_in_screen.dart';

void _toast(ScaffoldMessengerState messenger, String message, {bool error = false}) => messenger
  ..hideCurrentSnackBar()
  ..showSnackBar(SnackBar(content: Text(message), backgroundColor: error ? PingDuckColors.critical : null));

/// Every upgrade point opens Premium through here. Buying needs an email
/// account, so Premium follows the person to any phone; an anonymous user
/// creates one first. True once the plan is paid.
Future<bool> openPaywall(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  if (!billingSupported) {
    _toast(messenger, 'Subscriptions are available in the Android app for now.');
    return false;
  }
  final auth = ref.read(accountAuthProvider);
  if (auth.email == null) {
    final ok = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => const SignInScreen(
          startWithSignUp: true,
          lead: 'Create an account first, so Premium follows you to any phone you sign in on.',
        ),
      ),
    );
    if (ok != true || !context.mounted) return false;
    // The account may already have Premium from another phone.
    await ref.read(currentPlanProvider.notifier).refresh();
    if (!context.mounted) return false;
  }
  if (ref.read(currentPlanProvider).value?.isPaid ?? false) {
    _toast(messenger, 'Premium is already active on this account.');
    return true;
  }
  // The purchase must land on this account, even if the sign-in listener
  // hasn't told RevenueCat yet.
  try {
    await ref.read(billingProvider).identify(auth.accountId);
  } catch (_) {}
  if (!context.mounted) return false;
  final paid = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const PaywallScreen()));
  return paid == true;
}

/// Asks Google Play for this Google account's purchases, then waits for the
/// server to grant them. True when the plan is paid.
Future<bool> restorePurchases(BuildContext context, WidgetRef ref) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await ref.read(billingProvider).restore();
  } on BillingException catch (e) {
    _toast(messenger, e.message, error: true);
    return false;
  }
  final ok = await ref.read(currentPlanProvider.notifier).waitForPaid(timeout: const Duration(seconds: 15));
  _toast(messenger, ok ? 'Premium restored' : 'No active subscription found for this Google account.');
  return ok;
}

/// PingDuck Premium: what it adds, yearly or monthly, and the trial terms
/// Google requires before purchase. Pops with true once the server says the
/// plan is paid.
class PaywallScreen extends ConsumerStatefulWidget {
  const PaywallScreen({super.key});

  static const benefits = [
    'Unlimited scans from your phone',
    'The Homelab Agent on up to 2 networks, around the clock',
    'An alert when an unknown device joins',
    'Agent devices synced with their MAC address and maker',
  ];

  @override
  ConsumerState<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends ConsumerState<PaywallScreen> {
  late Future<List<PlanOffer>> _offers = _load();
  PlanOffer? _selected;
  bool _busy = false;

  /// After a purchase, while the webhook writes the entitlement.
  bool _confirming = false;

  Future<List<PlanOffer>> _load() async {
    final offers = await ref.read(billingProvider).offers();
    _selected = offers.firstOrNull;
    return offers;
  }

  void _retry() => setState(() => _offers = _load());

  void _close(String message, {required bool paid}) {
    if (!mounted) return;
    _toast(ScaffoldMessenger.of(context), message);
    Navigator.of(context).pop(paid);
  }

  Future<void> _buy(PlanOffer offer) async {
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _busy = true);
    try {
      switch (await ref.read(billingProvider).buy(offer)) {
        case PurchaseOutcome.purchased:
          if (!mounted) return;
          setState(() => _confirming = true);
          final ok = await ref.read(currentPlanProvider.notifier).waitForPaid();
          return _close(
            ok ? 'Premium is active' : 'Purchase received. Premium will turn on within a few minutes.',
            paid: ok,
          );
        case PurchaseOutcome.cancelled:
          break;
        case PurchaseOutcome.pending:
          _toast(messenger, 'Payment pending. Premium turns on once Google Play confirms it.');
      }
    } on BillingException catch (e) {
      _toast(messenger, e.message, error: true);
    }
    if (mounted) setState(() => _busy = false);
  }

  Future<void> _restore() async {
    setState(() => _busy = true);
    if (await restorePurchases(context, ref)) {
      if (mounted) Navigator.of(context).pop(true);
      return;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PREMIUM', style: PdText.labelLg),
        leading: IconButton(
          tooltip: 'Close',
          icon: const Icon(Icons.close),
          onPressed: _confirming ? null : () => Navigator.of(context).pop(false),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('PingDuck Premium', style: PdText.headlineMd),
          const SizedBox(height: 4),
          Text('Watch your network around the clock, not just when your phone is home.', style: PdText.bodyMd),
          const SizedBox(height: 16),
          PdPanel(
            title: 'What you get',
            icon: Icons.workspace_premium_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final b in PaywallScreen.benefits)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.check, size: 18, color: PingDuckColors.live),
                        const SizedBox(width: 10),
                        Expanded(child: Text(b, style: PdText.bodyMd)),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<PlanOffer>>(
            future: _offers,
            builder: (context, snap) => switch (snap) {
              AsyncSnapshot(connectionState: ConnectionState.waiting) => const Padding(
                padding: EdgeInsets.all(24),
                child: Center(child: CircularProgressIndicator()),
              ),
              AsyncSnapshot(:final data?) when data.isNotEmpty => _choices(data),
              AsyncSnapshot(hasError: true) => _unavailable('Couldn’t load prices. Check your connection.'),
              _ => _unavailable('Premium isn’t available to buy right now. Try again later.'),
            },
          ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              TextButton(onPressed: _busy ? null : _restore, child: const Text('RESTORE PURCHASES')),
              TextButton(onPressed: () => openExternalUrl(termsUrl), child: const Text('TERMS')),
              TextButton(onPressed: () => openExternalUrl(privacyUrl), child: const Text('PRIVACY')),
            ],
          ),
        ],
      ),
    );
  }

  Widget _unavailable(String message) => PdPanel(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(message, style: PdText.bodyMd),
        const SizedBox(height: 12),
        PdButton(label: 'Retry', icon: Icons.refresh, onPressed: _retry),
      ],
    ),
  );

  Widget _choices(List<PlanOffer> offers) {
    final chosen = _selected ?? offers.first;
    final trial = chosen.trialDays;
    final period = chosen.period;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final o in offers) ...[
          _OfferTile(
            offer: o,
            selected: o.id == chosen.id,
            onTap: _busy ? null : () => setState(() => _selected = o),
          ),
          const SizedBox(height: 8),
        ],
        const SizedBox(height: 8),
        PdButton(
          key: const Key('paywall_buy'),
          label: _confirming
              ? 'Turning on Premium…'
              : trial != null
              ? 'Start $trial-day free trial'
              : 'Subscribe',
          icon: Icons.workspace_premium_outlined,
          style: PdButtonStyle.primary,
          height: 52,
          onPressed: _busy ? null : () => _buy(chosen),
        ),
        const SizedBox(height: 10),
        Text(
          '${trial != null ? '$trial days free, then ' : ''}${chosen.priceString} per $period. Renews '
          'automatically until you cancel in Google Play, at least 24 hours before the period ends.',
          style: PdText.bodySm,
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}

class _OfferTile extends StatelessWidget {
  const _OfferTile({required this.offer, required this.selected, required this.onTap});
  final PlanOffer offer;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final yearly = offer.period == 'year';
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          key: Key('offer_${offer.period}'),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: selected ? PingDuckColors.canvas : PingDuckColors.surface1,
              border: Border.all(
                color: selected ? PingDuckColors.live : PingDuckColors.hairline,
                width: selected ? 2 : 1,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                  color: selected ? PingDuckColors.live : PingDuckColors.inkMuted,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(yearly ? 'Yearly' : 'Monthly', style: PdText.headlineSm),
                      const SizedBox(height: 2),
                      Text(
                        '${offer.priceString} / ${offer.period}'
                        '${offer.trialDays != null ? ' · ${offer.trialDays}-day free trial' : ''}',
                        style: PdText.bodySm,
                      ),
                    ],
                  ),
                ),
                if (offer.savingsPercent != null) PdChip('SAVE ${offer.savingsPercent}%', tone: PdTone.live),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
