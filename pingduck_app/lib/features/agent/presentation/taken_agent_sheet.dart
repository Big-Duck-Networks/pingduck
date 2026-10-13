import 'package:flutter/material.dart';

import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../domain/agent_platform.dart';
import 'flow_scaffold.dart';

/// Explains an agent that another account activated, and how to take it back.
/// An unpaired agent accepts the first valid code from anyone on its LAN, so
/// this is also what an owner sees if a guest got there first.
Future<void> showTakenAgentSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (context) => SafeArea(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Paired to another account', style: PdText.headlineSm),
          const SizedBox(height: 8),
          Text(
            'This agent reports its network to a different PingDuck account. If that isn\'t yours, someone else '
            'on this Wi-Fi may have activated it first. Reset it on the box: it forgets the pairing and the other '
            'account stops getting updates. Then tap Search again here and activate it from this phone.',
            style: PdText.bodyMd,
          ),
          const SizedBox(height: 16),
          Text('LINUX, PROXMOX OR RASPBERRY PI', style: PdText.labelMd),
          const SizedBox(height: 4),
          Text('Remove the container and its data, then run it again:', style: PdText.bodySm),
          const CommandBlock(resetAgentCommand),
          const CommandBlock(agentRunCommand),
          const SizedBox(height: 16),
          Text('SYNOLOGY OR QNAP', style: PdText.labelMd),
          const SizedBox(height: 4),
          Text(
            'Delete the pingduck-agent project and its pingduck volume, then create the project again.',
            style: PdText.bodySm,
          ),
          const SizedBox(height: 16),
          Text('WINDOWS', style: PdText.labelMd),
          const SizedBox(height: 4),
          Text(
            'Uninstall PingDuck and answer Yes when it asks to remove this PC\'s pairing, then install it again '
            'from pingduck.app/agent.',
            style: PdText.bodySm,
          ),
          const SizedBox(height: 16),
          Text(
            'The agent\'s log shows the address that activated it, in a line starting "pair: request from".',
            style: PdText.bodySm,
          ),
          const SizedBox(height: 16),
          PdButton(label: 'Got it', onPressed: () => Navigator.of(context).pop()),
        ],
      ),
    ),
  ),
);
