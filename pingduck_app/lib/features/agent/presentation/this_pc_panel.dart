import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/desktop/desktop.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../auth/account_auth.dart';
import '../../auth/sign_in_screen.dart';
import '../application/agent_pairing_controller.dart';
import '../application/agent_status.dart';
import '../data/agent_lan_client.dart';
import '../data/agent_repository.dart';
import '../domain/agent_unit.dart';
import 'add_unit_intro_screen.dart';
import 'flow_scaffold.dart';

/// The PingDuck Agent service on this PC, as its LAN API reports it on the
/// loopback address. Null when the service isn't running.
final localAgentProvider = FutureProvider.autoDispose<FoundAgent?>(
  (ref) => ref.read(agentLanClientProvider).info('127.0.0.1'),
);

final startWithWindowsProvider = FutureProvider.autoDispose<bool>(
  (ref) => StartWithWindows.enabled(),
);

/// Account tab, Windows only: this PC as a monitoring unit (Fing Desktop's
/// "sign in to get your data in sync") and Start with Windows.
class ThisPcPanel extends ConsumerStatefulWidget {
  const ThisPcPanel({super.key});

  @override
  ConsumerState<ThisPcPanel> createState() => _ThisPcPanelState();
}

class _ThisPcPanelState extends ConsumerState<ThisPcPanel> {
  bool _busy = false;

  void _snack(String text) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(text)));
  }

  Future<void> _monitor(FoundAgent local) async {
    setState(() => _busy = true);
    try {
      if (ref.read(accountAuthProvider).email == null) {
        final ok = await Navigator.of(
          context,
        ).push<bool>(MaterialPageRoute(builder: (_) => const SignInScreen()));
        if (ok != true) return;
      }
      if (await ref.read(agentRepositoryProvider).maxMonitoredNetworks() == 0) {
        if (mounted) {
          await pushAgentFlow<void>(context, 'premium', const PremiumRequiredScreen());
        }
        return;
      }
      // Same path as the phone pairing a LAN agent, against this PC.
      final pairing = ref.read(agentPairingProvider.notifier);
      final keepAlive = ref.listenManual(agentPairingProvider, (_, _) {});
      try {
        await pairing.activate(local);
        switch (ref.read(agentPairingProvider)) {
          case PairingActivated(:final networkLabel):
            _snack('This PC is now monitoring $networkLabel');
          case PairingFailed(:final failure):
            _snack(failure.message);
          default:
            break;
        }
      } finally {
        keepAlive.close();
      }
    } catch (_) {
      _snack('Couldn\'t reach PingDuck\'s servers. Check your connection.');
    } finally {
      ref.invalidate(localAgentProvider);
      ref.invalidate(myAgentsProvider);
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final local = ref.watch(localAgentProvider);
    final mine = {
      for (final a
          in ref.watch(myAgentsProvider).value ?? const <PairedAgent>[])
        a.id,
    };
    final startup = ref.watch(startWithWindowsProvider);

    final (
      String status,
      PdTone tone,
      String detail,
      Widget? action,
    ) = switch (local) {
      AsyncLoading() => (
        'CHECKING',
        PdTone.neutral,
        'Looking for the PingDuck Agent service…',
        null,
      ),
      AsyncData(value: null) || AsyncError() => (
        'NOT RUNNING',
        PdTone.critical,
        'The PingDuck Agent service isn\'t running on this PC. Reinstall PingDuck to restore it.',
        null,
      ),
      AsyncData(value: final FoundAgent a) when !a.paired => (
        'NOT MONITORING',
        PdTone.pending,
        'Use this PC as a monitoring unit: it scans the network around the clock, even with this window closed.',
        PdButton(
          label: _busy ? 'Adding…' : 'Monitor this network',
          icon: Icons.dns_outlined,
          style: PdButtonStyle.primary,
          onPressed: _busy ? null : () => _monitor(a),
        ),
      ),
      AsyncData(value: final FoundAgent a) when mine.contains(a.agentId) => (
        'MONITORING',
        PdTone.live,
        'This PC is a monitoring unit on your account. Manage it under Tools › Homelab Agent.',
        null,
      ),
      AsyncData() => (
        'OTHER ACCOUNT',
        PdTone.pending,
        'This PC is monitoring for a different PingDuck account. Revoke it there to add it to yours.',
        null,
      ),
    };

    return PdPanel(
      title: 'This PC',
      icon: Icons.computer,
      trailing: PdChip(status, tone: tone),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(detail, style: PdText.bodySm),
          if (action != null) ...[const SizedBox(height: 12), action],
          const SizedBox(height: 8),
          // Its own Material: the panel's background would hide the ink.
          Material(
            type: MaterialType.transparency,
            child: SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text('Start PingDuck with Windows', style: PdText.labelLg),
              subtitle: Text(
                'Opens in the tray when you sign in to Windows.',
                style: PdText.bodySm,
              ),
              activeThumbColor: PingDuckColors.live,
              value: startup.value ?? false,
              onChanged: startup.hasValue
                  ? (on) async {
                      await StartWithWindows.set(on);
                      ref.invalidate(startWithWindowsProvider);
                    }
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}
