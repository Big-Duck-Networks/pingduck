import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../shell/app_shell.dart';
import '../../tools/presentation/tools_screen.dart';
import '../domain/agent_unit.dart';
import 'flow_scaffold.dart';

/// Step 5: the agent is paired. Done goes to the Homelab Agent tool.
class AgentActivatedScreen extends ConsumerWidget {
  const AgentActivatedScreen({super.key, required this.agent, required this.networkLabel});
  final PairedAgent agent;
  final String networkLabel;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopScope(
      canPop: false,
      child: FlowScaffold(
        showBack: false,
        illustration: const IconTile(Icons.check, color: PingDuckColors.live),
        title: '${agent.name} is on watch',
        lead: 'It\'s paired with $networkLabel.',
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            PdField(label: 'Agent', value: agent.name),
            const SizedBox(height: 8),
            PdField(label: 'Network', value: networkLabel),
            if (agent.version != null) ...[const SizedBox(height: 8), PdField(label: 'Version', value: agent.version!)],
          ],
        ),
        actions: [
          FlowPrimaryButton(
            label: 'Done',
            onPressed: () {
              closeAgentFlow(context);
              ref.read(appTabProvider.notifier).go(AppTab.tools);
              ref.read(activeToolProvider.notifier).open(Tool.agent);
            },
          ),
        ],
      ),
    );
  }
}
