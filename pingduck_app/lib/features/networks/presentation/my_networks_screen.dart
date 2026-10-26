import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/lan_connectivity.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/local_storage.dart';
import '../../scanner/application/scan_controller.dart';

/// Saved networks; refreshed after every scan and every forget.
final myNetworksProvider = FutureProvider<List<NetworkSummary>>((ref) {
  ref.watch(scanControllerProvider.select((s) => (s.lastScanAt, s.networkId, s.devices.length)));
  return ref.read(localStoreProvider).networkSummaries();
});

/// Every network PingDuck has scanned, reached from the header chip.
class MyNetworksScreen extends ConsumerWidget {
  const MyNetworksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final networks = ref.watch(myNetworksProvider);
    final scan = ref.watch(scanControllerProvider);
    final online = ref.watch(lanConnectedProvider).isOnLan;
    // "Connected" means on this network right now, not merely last viewed.
    final currentId = online && scan.lan != null ? scan.networkId : null;

    return Scaffold(
      appBar: AppBar(
        title: Text('MY NETWORKS', style: PdText.labelLg),
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: switch (networks) {
        AsyncData(:final value) when value.isEmpty => const _Empty(),
        AsyncData(:final value) => ListView(
            padding: const EdgeInsets.all(16),
            children: [
              PdSectionHeader(
                title: 'My Networks',
                icon: Icons.wifi,
                badge: '${value.length} saved',
              ),
              const SizedBox(height: 8),
              Text('Networks this device has scanned. Each keeps its own devices, names and notes.',
                  style: PdText.bodySm),
              const SizedBox(height: 16),
              for (final n in value) ...[
                _NetworkCard(network: n, connected: n.id == currentId, scanning: scan.isScanning),
                const SizedBox(height: 12),
              ],
            ],
          ),
        AsyncError() => Center(child: Text('Could not read saved networks.', style: PdText.bodyMd)),
        _ => const Center(child: CircularProgressIndicator()),
      },
    );
  }
}

class _NetworkCard extends ConsumerWidget {
  const _NetworkCard({required this.network, required this.connected, required this.scanning});
  final NetworkSummary network;
  final bool connected;
  final bool scanning;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = network;
    return Container(
      decoration: BoxDecoration(
        color: connected ? PingDuckColors.surface1 : PingDuckColors.canvas,
        border: Border(
          top: BorderSide(color: connected ? PingDuckColors.live : PingDuckColors.ink, width: 2),
          left: BorderSide(color: PingDuckColors.partition),
          right: BorderSide(color: PingDuckColors.partition),
          bottom: BorderSide(color: PingDuckColors.partition),
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: PingDuckColors.canvas,
                  border: Border.all(color: PingDuckColors.partition),
                ),
                child: Icon(
                  n.ssid != null ? Icons.wifi : Icons.lan_outlined,
                  color: connected ? PingDuckColors.live : PingDuckColors.inkSecondary,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(n.name, style: PdText.headlineSm, maxLines: 1, overflow: TextOverflow.ellipsis),
                    if (n.ssid != null) Text(n.cidr, style: PdText.code.copyWith(color: PingDuckColors.route)),
                  ],
                ),
              ),
              if (connected) const PdChip('CONNECTED', tone: PdTone.live),
            ],
          ),
          const SizedBox(height: 12),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: PdField(label: 'Devices', value: '${n.deviceCount}')),
                const SizedBox(width: 8),
                Expanded(child: PdField(label: 'Gateway', value: n.gateway ?? '—')),
                const SizedBox(width: 8),
                Expanded(child: PdField(label: 'Last scan', value: _ago(n.lastScanAt))),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerRight,
            child: SizedBox(
              width: 190,
              child: PdButton(
                label: 'Forget network',
                icon: Icons.delete_outline,
                style: PdButtonStyle.destructive,
                height: 36,
                onPressed: connected && scanning ? null : () => _forget(context, ref),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _forget(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('FORGET ${network.name.toUpperCase()}?', style: PdText.labelLg),
        content: Text(
          'Removes its ${network.deviceCount} saved devices, including your names and notes. '
          'Scanning this network again starts fresh.',
          style: PdText.bodyMd,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('CANCEL')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('FORGET', style: PdText.labelLg.copyWith(color: PingDuckColors.critical)),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(scanControllerProvider.notifier).forgetNetwork(network.id);
    ref.invalidate(myNetworksProvider);
  }

  static String _ago(DateTime? t) {
    if (t == null) return 'never';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${d.inDays}d ago';
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const DuckLogo(size: 56),
            const SizedBox(height: 16),
            Text('No saved networks yet', style: PdText.headlineSm),
            const SizedBox(height: 6),
            Text('Networks appear here after their first scan.',
                style: PdText.bodyMd.copyWith(color: PingDuckColors.inkSecondary), textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
