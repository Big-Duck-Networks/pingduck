import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../tools/presentation/tools_screen.dart';
import '../application/agent_status.dart';
import '../data/agent_repository.dart';
import '../domain/agent_unit.dart';
import 'add_unit_intro_screen.dart';

/// The Homelab Agent tool: the account's paired agents with status and
/// revoke, or what an agent adds and how to add one.
class AgentScreen extends ConsumerWidget {
  const AgentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agents = ref.watch(myAgentsProvider);
    final list = agents.value ?? const <PairedAgent>[];
    return RefreshIndicator(
      onRefresh: () => ref.refresh(myAgentsProvider.future),
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const ToolBreadcrumb(Tool.agent),
          const SizedBox(height: 8),
          if (agents.isLoading && !agents.hasValue)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator(color: PingDuckColors.ink)),
            )
          else if (agents.hasError && list.isEmpty)
            PdPanel(
              title: 'Agents unavailable',
              icon: Icons.cloud_off_outlined,
              accent: PingDuckColors.pending,
              child: Text('Couldn\'t reach PingDuck\'s servers. Pull to try again.', style: PdText.bodyMd),
            )
          else if (list.isEmpty)
            const _NoAgent()
          else
            for (final a in list) ...[_AgentPanel(agent: a), const SizedBox(height: 16)],
          if (list.isEmpty) ...[const SizedBox(height: 16), const _WhatItAdds()],
          const SizedBox(height: 16),
          PdButton(
            label: list.isEmpty ? 'Add monitoring unit' : 'Add another monitoring unit',
            icon: Icons.add,
            style: list.isEmpty ? PdButtonStyle.primary : PdButtonStyle.secondary,
            onPressed: () => openAddMonitoringUnit(context),
          ),
        ],
      ),
    );
  }
}

class _NoAgent extends StatelessWidget {
  const _NoAgent();

  @override
  Widget build(BuildContext context) => PdPanel(
    background: PingDuckColors.canvas,
    child: Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: PingDuckColors.surface1,
            border: Border.all(color: PingDuckColors.partition),
          ),
          child: const Icon(Icons.dns_outlined, color: PingDuckColors.inkMuted),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DOCKER SNIFFER DAEMON', style: PdText.labelSm),
              const SizedBox(height: 2),
              Text('No agent paired', style: PdText.headlineSm),
            ],
          ),
        ),
        const PdChip('OFFLINE'),
      ],
    ),
  );
}

class _AgentPanel extends ConsumerWidget {
  const _AgentPanel({required this.agent});
  final PairedAgent agent;

  static String _ago(DateTime? t, DateTime now) {
    if (t == null) return 'never';
    final d = now.difference(t);
    if (d.inSeconds < 60) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes} min ago';
    if (d.inHours < 24) return '${d.inHours} h ago';
    return '${d.inDays} d ago';
  }

  static String _date(DateTime t) {
    final l = t.toLocal();
    return '${l.year}-${l.month.toString().padLeft(2, '0')}-${l.day.toString().padLeft(2, '0')}';
  }

  Future<void> _confirmRevoke(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('REVOKE AGENT?', style: PdText.labelLg),
        content: Text(
          '${agent.name} stops reporting at once. To use it again, add it as a new monitoring unit.',
          style: PdText.bodyMd,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('REVOKE', style: PdText.labelLg.copyWith(color: PingDuckColors.critical)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(agentRepositoryProvider).revoke(agent.id);
      ref.invalidate(myAgentsProvider);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('${agent.name} revoked')));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Couldn\'t revoke. Check your connection and try again.')));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final now = DateTime.now();
    final online = agent.isOnline(now);
    return PdPanel(
      background: PingDuckColors.canvas,
      accent: online ? PingDuckColors.live : PingDuckColors.partition,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: PingDuckColors.surface1,
                  border: Border.all(color: PingDuckColors.partition),
                ),
                child: Icon(Icons.dns_outlined, color: online ? PingDuckColors.live : PingDuckColors.inkMuted),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('MONITORING UNIT', style: PdText.labelSm),
                    const SizedBox(height: 2),
                    Text(agent.name, style: PdText.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              PdChip(online ? 'ONLINE' : 'OFFLINE', tone: online ? PdTone.live : PdTone.neutral),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: PdField(label: 'Last seen', value: _ago(agent.lastSeenAt, now))),
              const SizedBox(width: 8),
              Expanded(child: PdField(label: 'Version', value: agent.version ?? '—')),
              const SizedBox(width: 8),
              Expanded(child: PdField(label: 'Paired', value: _date(agent.createdAt))),
            ],
          ),
          const SizedBox(height: 12),
          PdButton(
            label: 'Revoke',
            icon: Icons.link_off,
            style: PdButtonStyle.destructive,
            onPressed: () => _confirmRevoke(context, ref),
          ),
        ],
      ),
    );
  }
}

class _WhatItAdds extends StatelessWidget {
  const _WhatItAdds();

  @override
  Widget build(BuildContext context) => PdPanel(
    title: 'What the agent adds',
    icon: Icons.shield_outlined,
    accent: PingDuckColors.ink,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (icon, title, body) in const [
          (
            Icons.memory,
            'MAC addresses & vendors',
            'Phones hide the ARP table. The agent sniffs ARP on your LAN, so every device gets its hardware address and maker.',
          ),
          (
            Icons.notification_important_outlined,
            'Intrusion alerts',
            'A push notification when an unknown device joins, the gateway MAC changes, or two hosts claim one IP.',
          ),
          (
            Icons.schedule,
            '24/7 monitoring',
            'Scans on an interval from a homelab box and syncs history, even when your phone is off the network.',
          ),
        ])
          Padding(
            padding: const EdgeInsets.only(bottom: 14),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 20, color: PingDuckColors.live),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: PdText.labelLg),
                      const SizedBox(height: 2),
                      Text(body, style: PdText.bodySm),
                    ],
                  ),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}
