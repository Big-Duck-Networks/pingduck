import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../data/agent_repository.dart';
import '../domain/agent_platform.dart';
import 'find_agent_screen.dart';
import 'flow_scaffold.dart';

/// Step 3: the install steps for one platform, Fing's numbered stepper.
class InstallStepsScreen extends ConsumerStatefulWidget {
  const InstallStepsScreen({super.key, required this.platform});
  final AgentPlatform platform;

  @override
  ConsumerState<InstallStepsScreen> createState() => _InstallStepsScreenState();
}

class _InstallStepsScreenState extends ConsumerState<InstallStepsScreen> {
  bool _sending = false;

  Future<void> _email() async {
    setState(() => _sending = true);
    String message;
    try {
      final to = await ref.read(agentRepositoryProvider).emailInstructions(widget.platform);
      message = 'Sent to $to';
    } on RateLimitedException {
      message = 'You\'ve had a few of these already. Try again in an hour.';
    } catch (_) {
      message = 'Couldn\'t send. Try again in a few minutes.';
    }
    if (!mounted) return;
    setState(() => _sending = false);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final steps = widget.platform.steps;
    return FlowScaffold(
      title: widget.platform.stepsTitle,
      lead: widget.platform.pitch,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [for (var i = 0; i < steps.length; i++) _Step(number: i + 1, step: steps[i], last: i == steps.length - 1)],
      ),
      actions: [
        FlowPrimaryButton(
          label: 'Find my agent',
          icon: Icons.wifi_find,
          onPressed: () => pushAgentFlow<void>(context, 'find', const FindAgentScreen()),
        ),
        PdButton(
          label: _sending ? 'Sending…' : 'Email me these steps',
          icon: Icons.mail_outline,
          onPressed: _sending ? null : _email,
        ),
        const MaybeLaterButton(),
      ],
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.number, required this.step, required this.last});
  final int number;
  final InstallStep step;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: 32,
            child: Column(
              children: [
                Container(
                  width: 32,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: PingDuckColors.canvas,
                    border: Border.all(color: PingDuckColors.ink, width: 1.5),
                  ),
                  child: Text('$number', style: PdText.labelLg),
                ),
                if (!last) const Expanded(child: DashedLine(vertical: true)),
              ],
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(top: 5, bottom: last ? 0 : 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(step.text, style: PdText.bodyLg),
                  if (step.command != null) CommandBlock(step.command!),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
