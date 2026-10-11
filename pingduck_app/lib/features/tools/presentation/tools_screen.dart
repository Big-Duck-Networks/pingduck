import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../agent/application/agent_status.dart';
import '../../agent/presentation/agent_screen.dart';
import '../../device_details/presentation/inspector_screen.dart';
import '../../scanner/application/scan_controller.dart';

/// The tools offered on the Tools tab.
enum Tool {
  nodeInspect(
    'Node Inspect',
    Icons.memory_outlined,
    'Everything known about one device, live ping with jitter and loss, port scan, Wake-on-LAN, notes.',
  ),
  agent(
    'Homelab Agent',
    Icons.dns_outlined,
    'A 24/7 sniffer on a homelab box: MAC addresses, intrusion alerts, history while your phone is away.',
  );

  const Tool(this.title, this.icon, this.description);
  final String title;
  final IconData icon;
  final String description;
}

/// The open tool, or null for the Tools hub.
final activeToolProvider = NotifierProvider<ActiveTool, Tool?>(ActiveTool.new);

class ActiveTool extends Notifier<Tool?> {
  @override
  Tool? build() => null;

  void open(Tool? tool) => state = tool;
}

class ToolsScreen extends ConsumerWidget {
  const ToolsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return switch (ref.watch(activeToolProvider)) {
      Tool.nodeInspect => const NodeInspectTool(),
      Tool.agent => const AgentScreen(),
      null => const _ToolsHub(),
    };
  }
}

class _ToolsHub extends ConsumerWidget {
  const _ToolsHub();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final paired = ref.watch(myAgentsProvider).value?.length ?? 0;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const PdSectionHeader(title: 'Tools', icon: Icons.handyman_outlined),
        const SizedBox(height: 8),
        Text('Diagnostics for the devices on ${scan.networkTitle}.', style: PdText.bodySm),
        const SizedBox(height: 16),
        for (final tool in Tool.values)
          _ToolCard(
            tool: tool,
            status: switch (tool) {
              Tool.nodeInspect => '${scan.devices.length} devices',
              Tool.agent => paired == 0 ? 'not paired' : '$paired paired',
            },
            onTap: () => ref.read(activeToolProvider.notifier).open(tool),
          ),
      ],
    );
  }
}

/// "← TOOLS / NAME" row at the top of every tool; the arrow returns to the hub.
class ToolBreadcrumb extends ConsumerWidget {
  const ToolBreadcrumb(this.tool, {super.key, this.onBack});
  final Tool tool;

  /// Overrides the default (back to the Tools hub), e.g. to leave a sub-view.
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        IconButton(
          tooltip: 'Tools',
          onPressed: onBack ?? () => ref.read(activeToolProvider.notifier).open(null),
          icon: const Icon(Icons.arrow_back, size: 20),
        ),
        Flexible(
          child: Text.rich(
            TextSpan(children: [
              TextSpan(text: 'TOOLS', style: PdText.labelLg.copyWith(color: PingDuckColors.inkSecondary)),
              TextSpan(text: '  /  ${tool.title.toUpperCase()}', style: PdText.labelLg),
            ]),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
      ],
    );
  }
}

class _ToolCard extends StatelessWidget {
  const _ToolCard({required this.tool, required this.status, required this.onTap});
  final Tool tool;
  final String status;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: tool.title,
      child: InkWell(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: PingDuckColors.surface1,
            border: Border(
              top: BorderSide(color: PingDuckColors.ink, width: 2),
              left: BorderSide(color: PingDuckColors.partition),
              right: BorderSide(color: PingDuckColors.partition),
              bottom: BorderSide(color: PingDuckColors.partition),
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: PingDuckColors.canvas,
                  border: Border.all(color: PingDuckColors.partition),
                ),
                child: Icon(tool.icon, color: PingDuckColors.live),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(child: Text(tool.title, style: PdText.headlineSm)),
                        const SizedBox(width: 8),
                        PdChip(status),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(tool.description, style: PdText.bodySm),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              const Icon(Icons.chevron_right, color: PingDuckColors.inkSecondary),
            ],
          ),
        ),
      ),
    );
  }
}
