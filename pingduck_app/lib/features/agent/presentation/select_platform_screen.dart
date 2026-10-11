import 'package:flutter/material.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../domain/agent_platform.dart';
import 'flow_scaffold.dart';
import 'install_steps_screen.dart';

/// Step 2: where the agent will run.
class SelectPlatformScreen extends StatefulWidget {
  const SelectPlatformScreen({super.key});

  @override
  State<SelectPlatformScreen> createState() => _SelectPlatformScreenState();
}

class _SelectPlatformScreenState extends State<SelectPlatformScreen> {
  AgentPlatform _selected = AgentPlatform.values.first;

  @override
  Widget build(BuildContext context) {
    return FlowScaffold(
      title: 'Where will PingDuck watch from?',
      lead: 'Pick the always-on computer on this network.',
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final group in PlatformGroup.values) ...[
            if (group != PlatformGroup.values.first) const SizedBox(height: 16),
            Text(group.label, style: PdText.labelSm),
            const SizedBox(height: 10),
            for (final p in AgentPlatform.values.where((p) => p.group == group)) ...[
              _PlatformCard(platform: p, selected: p == _selected, onTap: () => setState(() => _selected = p)),
              const SizedBox(height: 12),
            ],
          ],
        ],
      ),
      actions: [
        FlowPrimaryButton(
          label: 'Next',
          onPressed: () => pushAgentFlow<void>(context, 'steps', InstallStepsScreen(platform: _selected)),
        ),
        const MaybeLaterButton(),
      ],
    );
  }
}

class _PlatformCard extends StatelessWidget {
  const _PlatformCard({required this.platform, required this.selected, required this.onTap});
  final AgentPlatform platform;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      inMutuallyExclusiveGroup: true,
      selected: selected,
      button: true,
      label: platform.title,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          decoration: BoxDecoration(
            color: selected ? PingDuckColors.surface1 : PingDuckColors.canvas,
            border: Border.all(
              color: selected ? PingDuckColors.ink : PingDuckColors.partition,
              width: selected ? 2 : 1,
            ),
          ),
          child: Row(
            children: [
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: selected ? PingDuckColors.ink : PingDuckColors.inkMuted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(platform.title, style: PdText.headlineSm),
                    const SizedBox(height: 2),
                    Text(platform.subtitle, style: PdText.bodySm),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
