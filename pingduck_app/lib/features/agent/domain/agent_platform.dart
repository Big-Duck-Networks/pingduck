/// Where the published agent image lives; every platform runs the same one.
const agentImage = 'ghcr.io/big-duck-networks/pingduck-agent:latest';

/// The agent's LAN API port (agent/src/config.hpp).
const agentPort = 44480;

const _run = 'docker run -d --name pingduck-agent --restart unless-stopped \\\n'
    '  --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN \\\n'
    '  -v pingduck:/var/lib/pingduck \\\n'
    '  $agentImage';

/// Removes the container and its volume, which holds the pairing, so the
/// agent starts unpaired when it is run again.
const resetAgentCommand = 'docker rm -f pingduck-agent && docker volume rm pingduck';

/// The Linux run command, for running the agent again after a reset.
const agentRunCommand = _run;

/// The same container with a pairing code, for networks where the app can't
/// reach the agent by itself.
String runWithCode(String code) => 'docker run -d --name pingduck-agent --restart unless-stopped \\\n'
    '  --net=host --cap-add=NET_RAW --cap-add=NET_ADMIN \\\n'
    '  -v pingduck:/var/lib/pingduck -e PINGDUCK_PAIRING_CODE=$code \\\n'
    '  $agentImage';

/// Same as agent/compose.yaml.
const _compose = 'services:\n'
    '  pingduck-agent:\n'
    '    image: $agentImage\n'
    '    network_mode: host\n'
    '    cap_add: [NET_RAW, NET_ADMIN]\n'
    '    volumes: [pingduck:/var/lib/pingduck]\n'
    '    restart: unless-stopped\n'
    'volumes:\n'
    '  pingduck:';

class InstallStep {
  const InstallStep(this.text, {this.command});
  final String text;

  /// Shown under the text with a copy button.
  final String? command;
}

const _findSteps = [
  InstallStep('Keep this phone on the same Wi-Fi as the box'),
  InstallStep('Tap Find my agent'),
];

/// The two groups on the platform screen, as in Fing ("Fing Desktop",
/// "Fing Agent").
enum PlatformGroup {
  desktop('PINGDUCK DESKTOP'),
  agent('PINGDUCK AGENT');

  const PlatformGroup(this.label);
  final String label;
}

/// Where PingDuck can monitor from. Keep the steps in step with the email in
/// supabase/migrations/20261010120000_agent_pairing.sql (and
/// 20261011120000_agent_instructions_windows.sql for Windows).
enum AgentPlatform {
  windows(
    'Windows',
    'The PingDuck app for Windows 10 and 11, with the agent built in',
    'windows',
    'The versatile option: a full PingDuck on your PC that doubles as a home monitoring unit.',
    [
      InstallStep('Go to your PC now'),
      InstallStep('Type pingduck.app/agent in your browser'),
      InstallStep('Install PingDuck'),
      InstallStep('Sign in to get your data in sync'),
    ],
    group: PlatformGroup.desktop,
    customStepsTitle: 'Get PingDuck on Windows',
  ),
  linux(
    'Linux or Proxmox',
    'Docker on any 64-bit Linux box or VM',
    'linux',
    'One container. It finds the devices your phone can\'t see and keeps watching when you leave.',
    [
      InstallStep('Open a terminal on the box'),
      InstallStep('Run the agent', command: _run),
      ..._findSteps,
    ],
  ),
  raspberryPi(
    'Raspberry Pi',
    'Pi 3, 4 or 5 with 64-bit Raspberry Pi OS',
    'raspberry_pi',
    'A Pi on your network makes a quiet, always-on monitoring unit.',
    [
      InstallStep('Install Docker', command: 'curl -fsSL https://get.docker.com | sh'),
      InstallStep('Run the agent', command: 'sudo $_run'),
      ..._findSteps,
    ],
  ),
  nas(
    'Synology / QNAP NAS',
    'Container Manager or Container Station',
    'nas',
    'Your NAS is already on all day. Let it watch the network too.',
    [
      InstallStep('Open Container Manager (Synology) or Container Station (QNAP)'),
      InstallStep('Create a project from this compose file', command: _compose),
      ..._findSteps,
    ],
  );

  const AgentPlatform(
    this.title,
    this.subtitle,
    this.serverValue,
    this.pitch,
    this.steps, {
    this.group = PlatformGroup.agent,
    this.customStepsTitle,
  });

  final PlatformGroup group;
  final String? customStepsTitle;

  /// Headline of the install steps screen.
  String get stepsTitle => customStepsTitle ?? 'Install the agent on $title';

  final String title;
  final String subtitle;

  /// The `p_platform` value `email_agent_instructions` takes.
  final String serverValue;
  final String pitch;
  final List<InstallStep> steps;
}
