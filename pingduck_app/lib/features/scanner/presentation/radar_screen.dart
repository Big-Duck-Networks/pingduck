import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/scanner_bridge.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../application/scan_controller.dart';
import '../domain/discovered_device.dart';

/// The main "Cortex Map" / Radar view. For now a live device list driven by
/// [ScanController]; Phase 3 replaces it with the animated radar.
class RadarScreen extends ConsumerWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final text = Theme.of(context).textTheme;
    final scan = ref.watch(scanControllerProvider);
    final controller = ref.read(scanControllerProvider.notifier);
    final devices = scan.sortedDevices;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'PingDuck',
          style: text.titleLarge?.copyWith(color: PingDuckColors.duckYellow, fontWeight: FontWeight.w800),
        ),
      ),
      body: Column(
        children: [
          _StatusBar(state: scan),
          Expanded(
            child: devices.isEmpty
                ? _EmptyState(scanning: scan.isScanning)
                : ListView.separated(
                    itemCount: devices.length,
                    separatorBuilder: (_, _) => const Divider(height: 1, color: PingDuckColors.techDarkOutline),
                    itemBuilder: (_, i) => _DeviceTile(device: devices[i]),
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: scan.isScanning ? controller.cancel : controller.scan,
        backgroundColor: PingDuckColors.duckYellow,
        foregroundColor: PingDuckColors.techDark,
        icon: Icon(scan.isScanning ? Icons.stop : Icons.radar),
        label: Text(scan.isScanning ? 'Stop' : 'Scan'),
      ),
    );
  }
}

class _StatusBar extends StatelessWidget {
  const _StatusBar({required this.state});
  final ScanState state;

  @override
  Widget build(BuildContext context) {
    final online = state.devices.values.where((d) => d.isOnline).length;
    final (String label, Color color) = switch (state.phase) {
      ScanPhase.idle => ('Ready to scan', PingDuckColors.textMuted),
      ScanPhase.scanning => ('Scanning… $online found', PingDuckColors.duckYellow),
      ScanPhase.done => ('$online online${_took()}', PingDuckColors.online),
      ScanPhase.cancelled => ('Stopped · $online found', PingDuckColors.textMuted),
      ScanPhase.failed => (_failureText(state.failure), PingDuckColors.alert),
    };
    return Container(
      width: double.infinity,
      color: PingDuckColors.techDarkRaised,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          if (state.isScanning)
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: SizedBox.square(dimension: 14, child: CircularProgressIndicator(strokeWidth: 2)),
            ),
          Expanded(child: Text(label, style: TextStyle(color: color))),
        ],
      ),
    );
  }

  String _took() {
    final s = state.startedAt, f = state.finishedAt;
    if (s == null || f == null) return '';
    return ' · ${(f.difference(s).inMilliseconds / 1000).toStringAsFixed(1)}s';
  }

  static String _failureText(ScanFailure? f) => switch (f?.kind) {
        ScanFailureKind.noNetwork => 'Not on a local network. Connect to Wi-Fi and try again.',
        ScanFailureKind.permission => 'Scanning was blocked by a permission. Check Local Network access.',
        _ => 'Scan failed: ${f?.message ?? 'unknown error'}',
      };
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.scanning});
  final bool scanning;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.radar, size: 96, color: PingDuckColors.duckYellow),
          const SizedBox(height: 16),
          Text(scanning ? 'Listening for quacks…' : 'Quack. Tap Scan to map your network.', style: text.titleMedium),
        ],
      ),
    );
  }
}

class _DeviceTile extends StatelessWidget {
  const _DeviceTile({required this.device});
  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      device.ip,
      if (device.vendor != null) device.vendor!,
      if (device.model != null && device.model != device.displayName) device.model!,
    ].join(' · ');
    return ListTile(
      leading: Icon(Icons.circle, size: 12, color: device.isOnline ? PingDuckColors.online : PingDuckColors.offline),
      title: Text(
        device.displayName,
        style: TextStyle(color: device.isOnline ? PingDuckColors.textPrimary : PingDuckColors.textMuted),
      ),
      subtitle: Text(subtitle, style: const TextStyle(color: PingDuckColors.textMuted)),
      trailing: device.rttMs == null
          ? null
          : Text('${device.rttMs} ms', style: const TextStyle(color: PingDuckColors.textMuted)),
    );
  }
}
