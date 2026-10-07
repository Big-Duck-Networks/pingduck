import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/ffi/scanner_bridge.dart';
import '../../../core/network/lan_connectivity.dart';
import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/scan_quota.dart';
import '../../device_details/application/diagnostics_controller.dart';
import '../../shell/app_shell.dart';
import '../../tools/presentation/tools_screen.dart';
import '../application/scan_controller.dart';
import '../domain/discovered_device.dart';
import 'device_card.dart';
import 'radar_scope.dart';

enum LedgerSort {
  latency('LATENCY'),
  ip('IP'),
  name('NAME'),
  vendor('VENDOR'),
  lastSeen('LAST SEEN');

  const LedgerSort(this.label);
  final String label;
}

enum LedgerFilter { all, online, offline }

final ledgerSortProvider = NotifierProvider<_Choice<LedgerSort>, LedgerSort>(() => _Choice(LedgerSort.latency));
final ledgerFilterProvider = NotifierProvider<_Choice<LedgerFilter>, LedgerFilter>(() => _Choice(LedgerFilter.all));

class _Choice<T> extends Notifier<T> {
  _Choice(this.initial);
  final T initial;

  @override
  T build() => initial;

  void set(T value) => state = value;
}

List<DiscoveredDevice> sortAndFilter(Iterable<DiscoveredDevice> devices, LedgerSort sort, LedgerFilter filter) {
  final list = devices.where((d) => switch (filter) {
        LedgerFilter.all => true,
        LedgerFilter.online => d.isOnline,
        LedgerFilter.offline => !d.isOnline,
      }).toList();
  int byIp(DiscoveredDevice a, DiscoveredDevice b) => ScanState.ipKey(a.ip).compareTo(ScanState.ipKey(b.ip));
  list.sort((a, b) {
    if (a.isOnline != b.isOnline) return a.isOnline ? -1 : 1;
    final c = switch (sort) {
      LedgerSort.latency => (a.rttMs ?? 1 << 30).compareTo(b.rttMs ?? 1 << 30),
      LedgerSort.ip => 0,
      LedgerSort.name => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()),
      LedgerSort.vendor => (a.vendor ?? '~').toLowerCase().compareTo((b.vendor ?? '~').toLowerCase()),
      LedgerSort.lastSeen => (b.lastSeen ?? DateTime(0)).compareTo(a.lastSeen ?? DateTime(0)),
    };
    return c != 0 ? c : byIp(a, b);
  });
  return list;
}

/// Opens Node Inspect (Tools tab) on [d].
void inspect(WidgetRef ref, DiscoveredDevice d) {
  ref.read(selectedDeviceProvider.notifier).select(d.ip);
  ref.read(activeToolProvider.notifier).open(Tool.nodeInspect);
  ref.read(appTabProvider.notifier).go(AppTab.tools);
}

class OverviewScreen extends ConsumerWidget {
  const OverviewScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Off Wi-Fi, cached devices and the last network's telemetry would be stale
    // and misleading, so the page shows only the offline state.
    if (!ref.watch(lanConnectedProvider).isOnLan) return const _NotConnected();
    final scan = ref.watch(scanControllerProvider);
    final sort = ref.watch(ledgerSortProvider);
    final filter = ref.watch(ledgerFilterProvider);
    final controller = ref.read(scanControllerProvider.notifier);
    final ledger = sortAndFilter(scan.devices.values, sort, filter);

    return RefreshIndicator(
      color: PingDuckColors.live,
      onRefresh: controller.scan,
      child: CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            sliver: SliverList.list(children: [
              _TelemetryPanel(scan: scan),
              const SizedBox(height: 16),
              PdPanel(
                title: 'Latency map',
                icon: Icons.radar,
                trailing: _liveChip(scan),
                child: Column(
                  children: [
                    RadarScope(
                      devices: scan.sortedDevices,
                      scanning: scan.isScanning,
                      selfIp: scan.lan?.ip,
                      onTap: (d) => inspect(ref, d),
                    ),
                    const SizedBox(height: 12),
                    Row(children: [
                      Expanded(
                        child: PdButton(
                          label: 'Stop',
                          icon: Icons.pause_circle_outline,
                          onPressed: scan.isScanning ? controller.cancel : null,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PdButton(
                          label: scan.devices.isEmpty ? 'Scan' : 'Rescan',
                          icon: Icons.sync,
                          style: PdButtonStyle.accent,
                          onPressed: scan.isScanning ? null : controller.scan,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: PdButton(
                          label: 'Filter',
                          icon: Icons.filter_alt_outlined,
                          onPressed: () => _showFilter(context, ref),
                        ),
                      ),
                    ]),
                  ],
                ),
              ),
              if (scan.phase == ScanPhase.failed) ...[
                const SizedBox(height: 16),
                _FailureBanner(failure: scan.failure),
              ],
              const SizedBox(height: 24),
              PdSectionHeader(
                title: scan.networkTitle,
                icon: scan.networkName != null ? Icons.wifi : Icons.lan_outlined,
                badge: '${scan.onlineCount} online',
                trailing: TextButton.icon(
                  onPressed: () => _cycleSort(ref, sort),
                  icon: const Icon(Icons.sort, size: 18, color: PingDuckColors.inkSecondary),
                  label: Text('SORT: ${sort.label}', style: PdText.labelMd),
                ),
              ),
              const SizedBox(height: 12),
            ]),
          ),
          if (ledger.isEmpty)
            SliverToBoxAdapter(child: _EmptyLedger(scanning: scan.isScanning, hasCache: scan.devices.isNotEmpty))
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
              sliver: SliverList.separated(
                itemCount: ledger.length,
                separatorBuilder: (_, _) => const SizedBox(height: 12),
                itemBuilder: (_, i) => DeviceCard(
                  device: ledger[i],
                  kind: scan.kindOf(ledger[i]),
                  onTap: () => inspect(ref, ledger[i]),
                  onLongPress: () => renameDevice(context, ref, ledger[i]),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _liveChip(ScanState scan) => switch (scan.phase) {
        ScanPhase.scanning => const PdChip('LIVE', tone: PdTone.live),
        ScanPhase.failed => const PdChip('ERROR', tone: PdTone.critical),
        ScanPhase.done => PdChip('${scan.onlineCount} UP', tone: PdTone.live),
        ScanPhase.cancelled => const PdChip('STOPPED'),
        ScanPhase.idle => PdChip(scan.devices.isEmpty ? 'IDLE' : 'CACHED'),
      };

  void _cycleSort(WidgetRef ref, LedgerSort sort) =>
      ref.read(ledgerSortProvider.notifier).set(LedgerSort.values[(sort.index + 1) % LedgerSort.values.length]);

  void _showFilter(BuildContext context, WidgetRef ref) {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => Consumer(builder: (context, ref, _) {
        final filter = ref.watch(ledgerFilterProvider);
        final sort = ref.watch(ledgerSortProvider);
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('SHOW', style: PdText.labelMd),
                const SizedBox(height: 8),
                _Segmented<LedgerFilter>(
                  values: LedgerFilter.values,
                  selected: filter,
                  label: (f) => f.name.toUpperCase(),
                  onChanged: ref.read(ledgerFilterProvider.notifier).set,
                ),
                const SizedBox(height: 16),
                Text('SORT BY', style: PdText.labelMd),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final s in LedgerSort.values)
                      GestureDetector(
                        onTap: () => ref.read(ledgerSortProvider.notifier).set(s),
                        child: PdChip(s.label, tone: s == sort ? PdTone.ink : PdTone.neutral),
                      ),
                  ],
                ),
              ],
            ),
          ),
        );
      }),
    );
  }
}

/// Two or more adjacent square segments; the active one fills with ink.
class _Segmented<T> extends StatelessWidget {
  const _Segmented({required this.values, required this.selected, required this.label, required this.onChanged});
  final List<T> values;
  final T selected;
  final String Function(T) label;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(border: Border.all(color: PingDuckColors.partition)),
      child: Row(children: [
        for (final v in values)
          Expanded(
            child: GestureDetector(
              onTap: () => onChanged(v),
              child: Container(
                height: 40,
                alignment: Alignment.center,
                color: v == selected ? PingDuckColors.ink : PingDuckColors.canvas,
                child: Text(label(v),
                    style: PdText.labelLg.copyWith(color: v == selected ? PingDuckColors.canvas : PingDuckColors.inkMuted)),
              ),
            ),
          ),
      ]),
    );
  }
}

class _TelemetryPanel extends StatelessWidget {
  const _TelemetryPanel({required this.scan});
  final ScanState scan;

  @override
  Widget build(BuildContext context) {
    final lan = scan.lan;
    final took = scan.lastDuration;
    return PdPanel(
      title: 'Interface telemetry',
      icon: Icons.settings_input_antenna,
      accent: PingDuckColors.live,
      trailing: lan?.interfaceName == null ? null : PdChip(lan!.interfaceName!, tone: PdTone.route),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: PdField(
                label: 'Local IP / CIDR',
                value: lan?.ip ?? '—',
                sub: lan?.cidr,
                valueColor: PingDuckColors.ink,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: PdField(
                label: 'Gateway · DNS',
                value: lan?.gateway ?? '—',
                sub: lan?.dns == null ? null : 'DNS ${lan!.dns}',
                valueColor: PingDuckColors.live,
              ),
            ),
          ])),
          const SizedBox(height: 8),
          IntrinsicHeight(child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
              child: PdField(
                label: 'Sweep',
                value: scan.isScanning
                    ? 'running'
                    : took == null
                        ? '—'
                        : '${(took.inMilliseconds / 1000).toStringAsFixed(1)}s',
              ),
            ),
            const SizedBox(width: 8),
            Expanded(child: PdField(label: 'Found', value: '${scan.onlineCount}', sub: '${scan.devices.length} known')),
          ])),
          const SizedBox(height: 12),
          Text('PROTOCOL ENGINES', style: PdText.labelMd),
          const SizedBox(height: 8),
          Wrap(spacing: 8, runSpacing: 8, children: [
            PdChip('ICMP ${scan.countBy(DiscoverySource.icmp)} hosts', tone: PdTone.route),
            PdChip('mDNS ${scan.countBy(DiscoverySource.mdns)}', tone: PdTone.live),
            PdChip('SSDP ${scan.countBy(DiscoverySource.ssdp)}', tone: PdTone.pending),
            PdChip('DNS-PTR ${scan.countBy(DiscoverySource.dns)}'),
            if (scan.countBy(DiscoverySource.arp) > 0) PdChip('ARP ${scan.countBy(DiscoverySource.arp)}', tone: PdTone.live),
          ]),
        ],
      ),
    );
  }
}

class _NotConnected extends StatelessWidget {
  const _NotConnected();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: PingDuckColors.surface1,
                  border: Border.all(color: PingDuckColors.partition),
                ),
                child: const Icon(Icons.wifi_off, size: 34, color: PingDuckColors.inkSecondary),
              ),
            ),
            const SizedBox(height: 20),
            Text('Not connected to Wi-Fi', style: PdText.headlineMd, textAlign: TextAlign.center),
            const SizedBox(height: 8),
            Text(
              'PingDuck maps the devices on your local network. Connect to Wi-Fi (or Ethernet) and '
              'scanning starts automatically.',
              style: PdText.bodyMd.copyWith(color: PingDuckColors.inkSecondary),
              textAlign: TextAlign.center,
            ),
            if (canOpenWifiSettings) ...[
              const SizedBox(height: 24),
              const PdButton(
                label: 'Open Wi-Fi settings',
                icon: Icons.wifi,
                style: PdButtonStyle.primary,
                onPressed: openWifiSettings,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _FailureBanner extends StatelessWidget {
  const _FailureBanner({required this.failure});
  final ScanFailure? failure;

  @override
  Widget build(BuildContext context) {
    final text = switch (failure?.kind) {
      ScanFailureKind.noNetwork => 'Not on a local network. Connect to Wi-Fi and rescan.',
      ScanFailureKind.permission => 'Scanning was blocked by a permission. Allow Local Network access and rescan.',
      ScanFailureKind.quotaExceeded => "You've used today's free scans. More at "
          '${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(nextQuotaReset()))}, '
          'or go Premium for unlimited scans.',
      _ => 'Scan failed: ${failure?.message ?? 'unknown error'}',
    };
    return PdPanel(
      accent: PingDuckColors.critical,
      background: PingDuckColors.criticalFill,
      child: Row(children: [
        const Icon(Icons.error_outline, color: PingDuckColors.critical, size: 20),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: PdText.bodyMd.copyWith(color: PingDuckColors.critical))),
      ]),
    );
  }
}

class _EmptyLedger extends StatelessWidget {
  const _EmptyLedger({required this.scanning, required this.hasCache});
  final bool scanning;
  final bool hasCache;

  @override
  Widget build(BuildContext context) {
    final text = scanning
        ? 'Listening for quacks…'
        : hasCache
            ? 'Nothing matches this filter.'
            : 'Quack. Tap Scan to map your network.';
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
      child: Container(
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(border: Border.all(color: PingDuckColors.hairline)),
        child: Column(children: [
          const DuckLogo(size: 48),
          const SizedBox(height: 12),
          Text(text, style: PdText.bodyMd.copyWith(color: PingDuckColors.inkSecondary), textAlign: TextAlign.center),
        ]),
      ),
    );
  }
}

/// Rename dialog shared by the ledger and the Inspector. An empty name
/// restores the discovered one.
Future<void> renameDevice(BuildContext context, WidgetRef ref, DiscoveredDevice d) async {
  final controller = TextEditingController(text: d.customName ?? '');
  final name = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text('RENAME ${d.ip}', style: PdText.labelLg),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: d.hostname ?? d.model ?? d.ip),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
        TextButton(onPressed: () => Navigator.pop(context, controller.text), child: const Text('SAVE')),
      ],
    ),
  );
  if (name != null) await ref.read(scanControllerProvider.notifier).rename(d.ip, name);
}
