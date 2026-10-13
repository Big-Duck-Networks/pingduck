import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../auth/account_auth.dart';
import '../../auth/sign_in_screen.dart';
import '../../subscription/presentation/paywall_screen.dart';
import '../data/agent_repository.dart';
import 'flow_scaffold.dart';
import 'select_platform_screen.dart';

/// Opens Add monitoring unit (Fing's flow, PingDuck's look) from anywhere.
Future<void> openAddMonitoringUnit(BuildContext context) =>
    pushAgentFlow<void>(context, 'intro', const AddUnitIntroScreen());

/// Step 1: what an agent adds. Let's start checks for an account and a plan
/// with monitoring before going on.
class AddUnitIntroScreen extends ConsumerStatefulWidget {
  const AddUnitIntroScreen({super.key});

  @override
  ConsumerState<AddUnitIntroScreen> createState() => _AddUnitIntroScreenState();
}

class _AddUnitIntroScreenState extends ConsumerState<AddUnitIntroScreen> {
  bool _busy = false;

  static const _benefits = [
    'Get every device\'s MAC address and maker, which phones can\'t see',
    'Scan around the clock, even when your phone is away',
    'Alert you when an unknown device joins',
  ];

  Future<void> _start() async {
    setState(() => _busy = true);
    try {
      if (ref.read(accountAuthProvider).email == null) {
        final ok = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
        if (ok != true || !mounted) return;
      }
      final int slots;
      try {
        slots = await ref.read(agentRepositoryProvider).maxMonitoredNetworks();
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Couldn\'t reach PingDuck\'s servers. Check your connection.')),
          );
        }
        return;
      }
      if (!mounted) return;
      slots == 0
          ? await pushAgentFlow<void>(context, 'premium', const PremiumRequiredScreen())
          : await pushAgentFlow<void>(context, 'platform', const SelectPlatformScreen());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      illustration: const _PhoneToAgent(),
      title: 'Watch your network around the clock',
      lead: 'A PingDuck agent on an always-on box can:',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final b in _benefits)
            Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.check, color: PingDuckColors.live, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text(b, style: PdText.bodyLg)),
                ],
              ),
            ),
        ],
      ),
      actions: [
        FlowPrimaryButton(label: _busy ? 'Checking…' : 'Let\'s start', onPressed: _busy ? null : _start),
        const MaybeLaterButton(),
      ],
    );
  }
}

/// Phone, dashed link, agent box with the duck: what pairing connects.
class _PhoneToAgent extends StatelessWidget {
  const _PhoneToAgent();

  @override
  Widget build(BuildContext context) {
    return ExcludeSemantics(
      child: SizedBox(
        width: 240,
        height: 96,
        child: Row(
          children: [
            const IconTile(Icons.smartphone),
            const Expanded(child: Padding(padding: EdgeInsets.symmetric(horizontal: 10), child: DashedLine())),
            IconTile(
              Icons.dns_outlined,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  const Icon(Icons.dns_outlined, size: 32, color: PingDuckColors.ink),
                  Positioned(right: 4, bottom: 4, child: const DuckLogo(size: 20)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shown instead of step 2 when the plan has no monitoring (Free). Once
/// Premium is bought the flow carries on to step 2.
class PremiumRequiredScreen extends ConsumerWidget {
  const PremiumRequiredScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return FlowScaffold(
      illustration: const IconTile(Icons.workspace_premium_outlined, color: PingDuckColors.pending),
      title: 'Monitoring is a Premium feature',
      lead: 'Premium runs the agent on up to 2 networks, keeps the full device history and sends alerts.',
      body: PdPanel(
        title: 'On Free you keep',
        icon: Icons.check_circle_outline,
        child: Text('3 scans a day from your phone, the network tools and device names.', style: PdText.bodyMd),
      ),
      actions: [
        FlowPrimaryButton(
          label: 'See Premium',
          icon: Icons.workspace_premium_outlined,
          onPressed: () async {
            if (!await openPaywall(context, ref) || !context.mounted) return;
            await Navigator.of(context).pushReplacement(
              MaterialPageRoute<void>(
                settings: const RouteSettings(name: '${agentFlowPrefix}platform'),
                builder: (_) => const SelectPlatformScreen(),
              ),
            );
          },
        ),
        const MaybeLaterButton(),
      ],
    );
  }
}
