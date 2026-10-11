import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../scanner/application/scan_controller.dart';
import '../../shell/app_shell.dart';
import '../../tools/presentation/tools_screen.dart';
import '../application/agent_pairing_controller.dart';
import '../domain/agent_platform.dart';
import '../domain/agent_unit.dart';
import 'agent_activated_screen.dart';
import 'flow_scaffold.dart';

/// Step 4: search the LAN for agents, then activate one. No Fing reference
/// exists for this screen; it follows the flow's structure.
class FindAgentScreen extends ConsumerStatefulWidget {
  const FindAgentScreen({super.key});

  @override
  ConsumerState<FindAgentScreen> createState() => _FindAgentScreenState();
}

class _FindAgentScreenState extends ConsumerState<FindAgentScreen> {
  FoundAgent? _chosen;

  @override
  void initState() {
    super.initState();
    Future.microtask(() => ref.read(agentPairingProvider.notifier).search());
  }

  AgentPairingController get _ctrl => ref.read(agentPairingProvider.notifier);

  void _search() {
    setState(() => _chosen = null);
    _ctrl.search();
  }

  void _openHomelabAgent() {
    closeAgentFlow(context);
    ref.read(appTabProvider.notifier).go(AppTab.tools);
    ref.read(activeToolProvider.notifier).open(Tool.agent);
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(agentPairingProvider, (_, next) {
      if (next is PairingActivated) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: '${agentFlowPrefix}activated'),
            builder: (_) => AgentActivatedScreen(agent: next.agent, networkLabel: next.networkLabel),
          ),
        );
      }
    });
    final state = ref.watch(agentPairingProvider);
    final network = ref.watch(scanControllerProvider.select((s) => s.networkTitle));

    final (title, lead) = switch (state) {
      PairingSearching() => ('Looking for your agent', 'Searching $network for PingDuck agents…'),
      PairingFound(:final agents) => (
        agents.length == 1 ? 'Found an agent' : 'Found ${agents.length} agents',
        'Pick the one to add to $network.',
      ),
      PairingNoneFound() => ('No agent found', 'Nothing on $network answered as a PingDuck agent.'),
      PairingUnreachable(:final ips) => (
        ips.length == 1 ? 'Found an agent, but can\'t connect' : 'Found agents, but can\'t connect',
        'Something on the network is blocking this phone from reaching it.',
      ),
      PairingActivating(:final agent) => ('Adding ${agent.name}', 'This takes a few seconds.'),
      PairingManualCode() => ('Pair with a code', 'For a box the phone can\'t reach, like one on another VLAN.'),
      PairingActivated() => ('Activated', null),
      PairingFailed() => ('That didn\'t work', null),
    };

    return FlowScaffold(
      title: title,
      lead: lead,
      body: switch (state) {
        PairingSearching() || PairingActivated() => const _Searching(),
        PairingFound(:final agents, :final unreachable) => _FoundList(
          agents: agents,
          unreachable: unreachable,
          chosen: _chosen,
          onChoose: (a) => setState(() => _chosen = a),
          onYours: _openHomelabAgent,
        ),
        PairingNoneFound() => const _NoneFound(),
        PairingUnreachable(:final ips) => _Unreachable(ips: ips),
        PairingActivating(:final agent, :final step) => _Activating(agent: agent, step: step),
        PairingManualCode(:final code, :final expiresAt, :final expired) => _ManualCode(
          code: code,
          expiresAt: expiresAt,
          expired: expired,
        ),
        PairingFailed(:final failure) => PdPanel(
          title: 'Not added',
          icon: Icons.error_outline,
          accent: PingDuckColors.critical,
          child: Text(failure.message, style: PdText.bodyMd),
        ),
      },
      actions: [
        ...switch (state) {
          PairingSearching() || PairingActivating() || PairingActivated() => const <Widget>[],
          PairingFound() => [
            if (_chosen != null)
              FlowPrimaryButton(label: 'Activate ${_chosen!.name}', onPressed: () => _ctrl.activate(_chosen!)),
            PdButton(label: 'Search again', icon: Icons.refresh, onPressed: _search),
          ],
          PairingNoneFound() || PairingUnreachable() => [
            FlowPrimaryButton(label: 'Search again', icon: Icons.refresh, onPressed: _search),
            PdButton(label: 'Use a pairing code', icon: Icons.pin_outlined, onPressed: _ctrl.startManualCode),
          ],
          PairingManualCode(:final expired) => [
            if (expired) FlowPrimaryButton(label: 'New code', onPressed: _ctrl.startManualCode),
            PdButton(label: 'Search the network instead', icon: Icons.wifi_find, onPressed: _search),
          ],
          PairingFailed(:final failure) => [
            FlowPrimaryButton(label: 'Try again', icon: Icons.refresh, onPressed: _search),
            if (failure == PairingFailure.notConfirmed)
              PdButton(label: 'Open Homelab Agent', icon: Icons.dns_outlined, onPressed: _openHomelabAgent),
          ],
        },
        const MaybeLaterButton(),
      ],
    );
  }
}

class _Searching extends StatelessWidget {
  const _Searching();

  @override
  Widget build(BuildContext context) => PdPanel(
    title: 'Searching',
    icon: Icons.wifi_find,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const LinearProgressIndicator(color: PingDuckColors.ink, backgroundColor: PingDuckColors.surface2, minHeight: 3),
        const SizedBox(height: 12),
        Text('Agents answer UPnP searches on the local network. Keep this phone on the same Wi-Fi.', style: PdText.bodySm),
      ],
    ),
  );
}

class _FoundList extends StatelessWidget {
  const _FoundList({
    required this.agents,
    this.unreachable = const [],
    required this.chosen,
    required this.onChoose,
    required this.onYours,
  });
  final List<(FoundAgent, AgentAvailability)> agents;
  final List<String> unreachable;
  final FoundAgent? chosen;
  final ValueChanged<FoundAgent> onChoose;
  final VoidCallback onYours;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (agent, availability) in agents) ...[
          _AgentCard(
            agent: agent,
            availability: availability,
            selected: chosen?.instanceId == agent.instanceId,
            onTap: switch (availability) {
              AgentAvailability.available => () => onChoose(agent),
              AgentAvailability.yours => onYours,
              AgentAvailability.taken => null,
            },
          ),
          const SizedBox(height: 12),
        ],
        if (unreachable.isNotEmpty)
          Text(
            'Also announced at ${unreachable.join(', ')}, but not answering on port $agentPort. '
            'A firewall or VM network filter may be in the way.',
            style: PdText.bodySm,
          ),
      ],
    );
  }
}

class _AgentCard extends StatelessWidget {
  const _AgentCard({required this.agent, required this.availability, required this.selected, this.onTap});
  final FoundAgent agent;
  final AgentAvailability availability;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final (chip, tone) = switch (availability) {
      AgentAvailability.available => ('AVAILABLE', PdTone.live),
      AgentAvailability.yours => ('YOURS', PdTone.neutral),
      AgentAvailability.taken => ('TAKEN', PdTone.pending),
    };
    return Semantics(
      button: onTap != null,
      selected: selected,
      label: '${agent.name}, ${chip.toLowerCase()}',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: selected ? PingDuckColors.surface1 : PingDuckColors.canvas,
            border: Border.all(color: selected ? PingDuckColors.ink : PingDuckColors.partition, width: selected ? 2 : 1),
          ),
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
                    child: const Icon(Icons.dns_outlined, color: PingDuckColors.ink),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(agent.name, style: PdText.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                        const SizedBox(height: 2),
                        Text('${agent.ip} · v${agent.version}', style: PdText.bodySm),
                      ],
                    ),
                  ),
                  PdChip(chip, tone: tone),
                ],
              ),
              if (availability == AgentAvailability.taken) ...[
                const SizedBox(height: 10),
                Text(
                  'Activated by another account. Revoke it there, or wipe the agent\'s volume to start over.',
                  style: PdText.bodySm,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _NoneFound extends StatelessWidget {
  const _NoneFound();

  static const _checks = [
    ('The container is running', 'docker ps'),
    ('It uses host networking', '--net=host'),
    ('This phone is on the same Wi-Fi, not a guest network', null),
    ('The box\'s firewall allows port $agentPort and UDP 1900', null),
    ('If the box is a VM, its host isn\'t filtering its traffic (Proxmox firewall, libvirt network filters)', null),
  ];

  @override
  Widget build(BuildContext context) => PdPanel(
    title: 'Check on the box',
    icon: Icons.checklist,
    accent: PingDuckColors.pending,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final (text, code) in _checks)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right, size: 18, color: PingDuckColors.inkSecondary),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text.rich(
                    TextSpan(
                      children: [
                        TextSpan(text: text, style: PdText.bodyMd),
                        if (code != null) ...[const TextSpan(text: '  '), TextSpan(text: code, style: PdText.code)],
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        Text('On another VLAN or behind a VPN? Use a pairing code instead.', style: PdText.bodySm),
      ],
    ),
  );
}

/// SSDP reached the phone but TCP to the agent didn't: name the usual
/// suspects instead of saying nothing was found.
class _Unreachable extends StatelessWidget {
  const _Unreachable({required this.ips});
  final List<String> ips;

  static const _causes = [
    'A firewall on the box blocks TCP port $agentPort (ufw, firewalld, the NAS firewall)',
    'The box is a VM and its host filters its traffic (Proxmox firewall, libvirt network filters)',
    'The Wi-Fi isolates clients from each other (guest networks, "AP isolation")',
  ];

  @override
  Widget build(BuildContext context) => PdPanel(
    title: 'Can\'t connect',
    icon: Icons.portable_wifi_off,
    accent: PingDuckColors.pending,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'An agent announced itself at ${ips.join(', ')}, but didn\'t answer on port $agentPort. Check:',
          style: PdText.bodyMd,
        ),
        const SizedBox(height: 10),
        for (final c in _causes)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.only(top: 2),
                  child: Icon(Icons.chevron_right, size: 18, color: PingDuckColors.inkSecondary),
                ),
                const SizedBox(width: 6),
                Expanded(child: Text(c, style: PdText.bodyMd)),
              ],
            ),
          ),
        Text('Can\'t change the network? Use a pairing code instead.', style: PdText.bodySm),
      ],
    ),
  );
}

class _Activating extends StatelessWidget {
  const _Activating({required this.agent, required this.step});
  final FoundAgent agent;
  final ActivationStep step;

  @override
  Widget build(BuildContext context) {
    final rows = [
      (ActivationStep.registering, 'Registering this network'),
      (ActivationStep.sending, 'Sending the code to ${agent.name}'),
      (ActivationStep.confirming, 'Waiting for ${agent.name} to confirm'),
    ];
    return PdPanel(
      title: 'Activating',
      icon: Icons.link,
      child: Column(
        children: [
          for (final (s, label) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: s.index < step.index
                        ? const Icon(Icons.check, size: 20, color: PingDuckColors.live)
                        : s == step
                        ? const CircularProgressIndicator(strokeWidth: 2, color: PingDuckColors.ink)
                        : const Icon(Icons.circle_outlined, size: 16, color: PingDuckColors.inkMuted),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      label,
                      style: PdText.bodyMd.copyWith(
                        color: s.index > step.index ? PingDuckColors.inkMuted : PingDuckColors.ink,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _ManualCode extends StatefulWidget {
  const _ManualCode({required this.code, required this.expiresAt, required this.expired});
  final String code;
  final DateTime expiresAt;
  final bool expired;

  @override
  State<_ManualCode> createState() => _ManualCodeState();
}

class _ManualCodeState extends State<_ManualCode> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) => setState(() {}));
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final left = widget.expiresAt.difference(DateTime.now());
    final expired = widget.expired || left.isNegative;
    final mmss = '${left.inMinutes}:${(left.inSeconds % 60).toString().padLeft(2, '0')}';
    final grouped = '${widget.code.substring(0, 4)} ${widget.code.substring(4)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PdPanel(
          title: 'Pairing code',
          icon: Icons.pin_outlined,
          accent: expired ? PingDuckColors.critical : PingDuckColors.live,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SelectableText(
                grouped,
                style: PdText.displayMobile.copyWith(
                  fontFamily: PdText.code.fontFamily,
                  letterSpacing: 4,
                  color: expired ? PingDuckColors.inkMuted : PingDuckColors.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                expired ? 'Expired. Get a new code.' : 'Expires in $mmss · works once',
                style: PdText.code.copyWith(color: expired ? PingDuckColors.critical : PingDuckColors.inkSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text('Start the agent on the box with the code:', style: PdText.bodyMd),
        CommandBlock(runWithCode(widget.code)),
        const SizedBox(height: 16),
        if (!expired)
          Row(
            children: [
              const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: PingDuckColors.ink),
              ),
              const SizedBox(width: 10),
              Expanded(child: Text('Waiting for the agent to check in…', style: PdText.bodySm)),
            ],
          ),
      ],
    );
  }
}
