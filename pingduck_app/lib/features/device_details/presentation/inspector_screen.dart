import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../../services/supabase_sync.dart';
import '../../scanner/application/scan_controller.dart';
import '../../scanner/domain/device_kind.dart';
import '../../scanner/domain/discovered_device.dart';
import '../../recognition/fingerprint.dart';
import '../../recognition/learned_labels.dart';
import '../../recognition/recognition.dart';
import '../../scanner/presentation/overview_screen.dart' show renameDevice;
import '../../tools/presentation/tools_screen.dart';
import '../application/diagnostics_controller.dart';
import 'label_editor.dart';
import 'recognition_panels.dart';

/// Node Inspect tool: pick a device, then everything known about it plus
/// live diagnostics.
class NodeInspectTool extends ConsumerWidget {
  const NodeInspectTool({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scan = ref.watch(scanControllerProvider);
    final ip = ref.watch(selectedDeviceProvider);
    final device = ip == null ? null : scan.devices[ip];
    if (device == null) return _Picker(scan: scan);
    return _Inspector(device: device, kind: scan.kindOf(device), scan: scan);
  }
}

class _Picker extends ConsumerWidget {
  const _Picker({required this.scan});
  final ScanState scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devices = scan.sortedDevices;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const ToolBreadcrumb(Tool.nodeInspect),
        const SizedBox(height: 8),
        Text('Pick a device, or tap one on the radar or in the device list.', style: PdText.bodySm),
        const SizedBox(height: 16),
        if (devices.isEmpty)
          Text(
            'No devices yet. Run a scan from Overview.',
            style: PdText.bodyMd.copyWith(color: PingDuckColors.inkSecondary),
          ),
        for (final d in devices)
          InkWell(
            onTap: () => ref.read(selectedDeviceProvider.notifier).select(d.ip),
            child: Container(
              padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
              decoration: const BoxDecoration(
                border: Border(bottom: BorderSide(color: PingDuckColors.hairline)),
              ),
              child: Row(
                children: [
                  Icon(scan.kindOf(d).icon, size: 20, color: d.isOnline ? PingDuckColors.ink : PingDuckColors.inkMuted),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(d.displayName, style: PdText.bodyMd, overflow: TextOverflow.ellipsis),
                  ),
                  if (d.displayName != d.ip) Text(d.ip, style: PdText.code.copyWith(color: PingDuckColors.route)),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

class _Inspector extends ConsumerWidget {
  const _Inspector({required this.device, required this.kind, required this.scan});
  final DiscoveredDevice device;
  final DeviceKind kind;
  final ScanState scan;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = device;
    final diag = ref.watch(diagnosticsProvider(d.ip));
    final ctrl = ref.read(diagnosticsProvider(d.ip).notifier);
    final liveRtt = diag.pings.isNotEmpty ? diag.pings.last : (d.isOnline ? d.rttMs : null);
    final fingerprint = Fingerprint.of(d);
    final learned = fingerprint == null ? null : ref.watch(learnedLabelsProvider).value?[fingerprint];
    final recognition = Recognizer.of(d, kind, learned: learned);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Breadcrumb strip.
        Row(
          children: [
            IconButton(
              tooltip: 'All devices',
              onPressed: () => ref.read(selectedDeviceProvider.notifier).select(null),
              icon: const Icon(Icons.arrow_back, size: 20),
            ),
            Text('NODE INSPECT', style: PdText.labelLg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                '/ ${scan.lan?.interfaceName ?? 'lan'}::${d.ip}',
                style: PdText.code.copyWith(color: PingDuckColors.inkSecondary),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            PdChip(
              liveRtt == null ? (d.isOnline ? 'LIVE' : 'OFFLINE') : 'LIVE ${liveRtt}ms',
              tone: d.isOnline ? PdTone.live : PdTone.neutral,
            ),
          ],
        ),
        const SizedBox(height: 12),
        _IdentityPanel(device: d, kind: kind, recognition: recognition),
        const SizedBox(height: 16),
        RecognitionPanels(recognition, onEdit: () => editDeviceLabel(context, ref, d, recognition)),
        const SizedBox(height: 16),
        _RttPanel(device: d, diag: diag, onToggle: ctrl.togglePing, subnet: scan.lan?.cidr),
        const SizedBox(height: 16),
        _PortPanel(diag: diag, onQuick: () => ctrl.scanPorts(), onDeep: () => ctrl.scanPorts(deep: true)),
        const SizedBox(height: 16),
        _ServicesPanel(device: d),
        const SizedBox(height: 16),
        _ControlPanel(device: d, diag: diag, broadcast: scan.lan?.broadcast),
        if (diag.error != null) ...[
          const SizedBox(height: 12),
          Text(diag.error!, style: PdText.bodySm.copyWith(color: PingDuckColors.critical)),
        ],
      ],
    );
  }
}

class _IdentityPanel extends ConsumerWidget {
  const _IdentityPanel({required this.device, required this.kind, required this.recognition});
  final DiscoveredDevice device;
  final DeviceKind kind;
  final Recognition recognition;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final d = device;
    final subtitle = [recognition.brand?.value, recognition.model?.value]
        .whereType<String>()
        .where((s) => s != d.displayName)
        .toSet()
        .join(' · ');
    return PdPanel(
      background: PingDuckColors.canvas,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: 56,
                height: 56,
                decoration: BoxDecoration(
                  color: PingDuckColors.surface1,
                  border: Border.all(color: PingDuckColors.partition),
                ),
                child: Icon(kind.icon, size: 28, color: PingDuckColors.live),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.displayName, style: PdText.headlineMd),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        PdChip(d.isOnline ? 'ONLINE' : 'OFFLINE', tone: d.isOnline ? PdTone.live : PdTone.neutral),
                        if (kind != DeviceKind.unknown) PdChip(kind.label, uppercase: true),
                      ],
                    ),
                    const SizedBox(height: 6),
                    if (d.displayName != d.ip || d.hostname != null)
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: d.ip,
                              style: PdText.codeLg.copyWith(color: PingDuckColors.route),
                            ),
                            if (d.hostname != null && d.hostname != d.displayName)
                              TextSpan(
                                text: '  (${d.hostname})',
                                style: PdText.code.copyWith(color: PingDuckColors.inkSecondary),
                              ),
                          ],
                        ),
                      ),
                    if (subtitle.isNotEmpty)
                      Text(subtitle, style: PdText.bodySm, maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Rename',
                onPressed: () => renameDevice(context, ref, d),
                icon: const Icon(Icons.edit_outlined, size: 20),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PdField(label: 'First seen', value: _date(d.firstSeen)),
              ),
              Expanded(
                child: PdField(label: 'Last seen', value: d.isOnline ? 'now' : _date(d.lastSeen)),
              ),
              Expanded(
                child: PdField(
                  label: 'Sources',
                  value: d.sources.isEmpty ? '—' : d.sources.map((s) => s.name).join('+'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _date(DateTime? t) {
    if (t == null) return '—';
    final d = DateTime.now().difference(t);
    if (d.inMinutes < 1) return 'just now';
    if (d.inHours < 1) return '${d.inMinutes}m ago';
    if (d.inDays < 1) return '${d.inHours}h ago';
    return '${t.year}-${t.month.toString().padLeft(2, '0')}-${t.day.toString().padLeft(2, '0')}';
  }
}

class _RttPanel extends StatelessWidget {
  const _RttPanel({required this.device, required this.diag, required this.onToggle, this.subnet});
  final DiscoveredDevice device;
  final DiagnosticsState diag;
  final VoidCallback onToggle;
  final String? subnet;

  @override
  Widget build(BuildContext context) {
    final d = device;
    String fmt(num? v) => v == null ? '—' : '${v is double ? v.toStringAsFixed(1) : v}ms';
    return PdPanel(
      title: 'Layer 2 telemetry & RTT',
      icon: Icons.lan_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Full width: a 17-character MAC doesn't fit half a phone screen.
          PdField(
            label: 'MAC physical',
            value: d.mac?.toUpperCase() ?? 'not visible',
            sub: d.mac == null ? 'needs the agent on this OS' : (d.vendor ?? 'unknown vendor'),
            valueColor: d.mac == null ? PingDuckColors.inkMuted : null,
          ),
          const SizedBox(height: 8),
          PdField(label: 'Subnet', value: subnet ?? '—'),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: PingDuckColors.canvas,
              border: Border.all(color: PingDuckColors.hairline),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        'ICMP RTT MONITOR (${diag.pings.length}/${DiagnosticsController.window})',
                        style: PdText.labelSm,
                      ),
                    ),
                    _stat('MIN', fmt(diag.minRtt), PingDuckColors.inkSecondary),
                    _stat('AVG', fmt(diag.avgRtt), PingDuckColors.live),
                    _stat('MAX', fmt(diag.maxRtt), PingDuckColors.inkSecondary),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(height: 72, child: CustomPaint(painter: _RttChart(diag.pings))),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        diag.pings.isEmpty
                            ? 'Start a live ping to measure latency, jitter and loss.'
                            : 'Jitter ${fmt(diag.jitter)} · Loss ${diag.lossPercent.toStringAsFixed(0)}%',
                        style: PdText.code.copyWith(color: PingDuckColors.inkSecondary),
                      ),
                    ),
                    SizedBox(
                      width: 130,
                      child: PdButton(
                        label: diag.pingRunning ? 'Stop' : 'Live ping',
                        icon: diag.pingRunning ? Icons.stop : Icons.network_ping,
                        height: 36,
                        style: diag.pingRunning ? PdButtonStyle.primary : PdButtonStyle.secondary,
                        onPressed: onToggle,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.only(left: 10),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Text(label, style: PdText.labelSm),
        Text(
          value,
          style: PdText.code.copyWith(color: color, fontWeight: FontWeight.w700),
        ),
      ],
    ),
  );
}

/// Segmented latency histogram: sharp 4 px columns, colour by threshold,
/// a crimson tick for each timeout.
class _RttChart extends CustomPainter {
  _RttChart(this.pings);
  final List<int?> pings;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()..color = PingDuckColors.hairline,
    );
    if (pings.isEmpty) return;
    final maxV = math.max(5, pings.whereType<int>().fold(0, math.max)).toDouble();
    const w = 4.0, gap = 2.0;
    final slots = (size.width / (w + gap)).floor();
    final shown = pings.length > slots ? pings.sublist(pings.length - slots) : pings;
    for (var i = 0; i < shown.length; i++) {
      final x = size.width - (shown.length - i) * (w + gap);
      final v = shown[i];
      if (v == null) {
        canvas.drawRect(Rect.fromLTWH(x, size.height - 6, w, 6), Paint()..color = PingDuckColors.critical);
        continue;
      }
      final h = math.max(2.0, (v / maxV) * (size.height - 4));
      canvas.drawRect(Rect.fromLTWH(x, size.height - h, w, h), Paint()..color = PingDuckColors.forRtt(v));
    }
  }

  @override
  bool shouldRepaint(covariant _RttChart old) => old.pings != pings;
}

class _PortPanel extends StatelessWidget {
  const _PortPanel({required this.diag, required this.onQuick, required this.onDeep});
  final DiagnosticsState diag;
  final VoidCallback onQuick;
  final VoidCallback onDeep;

  @override
  Widget build(BuildContext context) {
    final running = diag.portScan == PortScanState.running;
    final done = diag.portScan == PortScanState.done;
    final open = diag.openPorts.toList()..sort();
    final deep = diag.scannedPorts.length > commonPorts.length;
    return PdPanel(
      title: 'Port matrix recon',
      icon: Icons.track_changes,
      trailing: PdChip(done ? '${open.length} open / ${diag.scannedPorts.length}' : 'TCP connect'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (running) ...[
            const LinearProgressIndicator(),
            const SizedBox(height: 8),
            Text('Probing ${diag.scannedPorts.length} ports…', style: PdText.code),
          ] else if (!done)
            Text(
              'Checks which TCP ports accept connections. Closed and filtered ports look the same from here.',
              style: PdText.bodySm,
            )
          else if (open.isEmpty)
            Text('No open ports among the ${diag.scannedPorts.length} probed.', style: PdText.bodySm)
          else
            for (final p in open) _PortRow(info: portInfo(p)),
          if (done && !deep) ...[
            const SizedBox(height: 8),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                for (final p in commonPorts.where((p) => !diag.openPorts.contains(p.port)))
                  PdChip('${p.port}', tone: PdTone.neutral),
              ],
            ),
            const SizedBox(height: 4),
            Text('No answer on the ports above.', style: PdText.labelSm.copyWith(color: PingDuckColors.inkMuted)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PdButton(label: 'Quick scan', icon: Icons.bolt, onPressed: running ? null : onQuick),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PdButton(
                  label: 'Deep 1-1024',
                  icon: Icons.manage_search,
                  style: PdButtonStyle.primary,
                  onPressed: running ? null : onDeep,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortRow extends StatelessWidget {
  const _PortRow({required this.info});
  final PortInfo info;

  @override
  Widget build(BuildContext context) {
    final risky = info.risk != null;
    final color = risky ? PingDuckColors.pending : PingDuckColors.live;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: PingDuckColors.canvas,
        border: Border(
          left: BorderSide(color: color, width: 4),
          top: const BorderSide(color: PingDuckColors.hairline),
          right: const BorderSide(color: PingDuckColors.hairline),
          bottom: const BorderSide(color: PingDuckColors.hairline),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text('${info.port}/TCP', style: PdText.codeLg),
                    const SizedBox(width: 8),
                    PdChip(info.service, tone: PdTone.route),
                  ],
                ),
                if (risky) ...[
                  const SizedBox(height: 4),
                  Text(info.risk!, style: PdText.code.copyWith(color: PingDuckColors.pending)),
                ],
              ],
            ),
          ),
          PdChip('OPEN', tone: risky ? PdTone.pending : PdTone.live),
        ],
      ),
    );
  }
}

class _ServicesPanel extends StatelessWidget {
  const _ServicesPanel({required this.device});
  final DiscoveredDevice device;

  @override
  Widget build(BuildContext context) {
    final d = device;
    final mdns = d.services.where((s) => s.startsWith('_')).toList();
    final upnp = d.services.where((s) => s.startsWith('upnp:')).toList();
    final hasSsdp = d.sources.contains(DiscoverySource.ssdp);
    return PdPanel(
      title: 'Service broadcasts & UPnP',
      icon: Icons.cell_tower,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('MDNS ADVERTISED SERVICES', style: PdText.labelSm),
          const SizedBox(height: 8),
          if (mdns.isEmpty)
            Text('None advertised.', style: PdText.bodySm)
          else
            Wrap(spacing: 6, runSpacing: 6, children: [for (final s in mdns) PdChip('$s.local', tone: PdTone.route)]),
          const SizedBox(height: 12),
          Text('UPNP DISCOVERY DESCRIPTOR', style: PdText.labelSm),
          const SizedBox(height: 8),
          if (!hasSsdp)
            Text('Did not answer SSDP.', style: PdText.bodySm)
          else
            Container(
              padding: const EdgeInsets.all(10),
              color: PingDuckColors.surface2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _xml('friendlyName', d.hostname),
                  _xml('manufacturer', d.vendor),
                  _xml('modelName', d.model),
                  for (final t in upnp) _xml('type', t.substring(5)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _xml(String tag, String? value) => value == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '<$tag> ',
                  style: PdText.code.copyWith(color: PingDuckColors.inkMuted),
                ),
                TextSpan(
                  text: value,
                  style: PdText.code.copyWith(color: PingDuckColors.live),
                ),
              ],
            ),
          ),
        );
}

class _ControlPanel extends ConsumerStatefulWidget {
  const _ControlPanel({required this.device, required this.diag, this.broadcast});
  final DiscoveredDevice device;
  final DiagnosticsState diag;
  final String? broadcast;

  @override
  ConsumerState<_ControlPanel> createState() => _ControlPanelState();
}

class _ControlPanelState extends ConsumerState<_ControlPanel> {
  late final TextEditingController _notes = TextEditingController(text: widget.device.notes ?? '');

  @override
  void didUpdateWidget(_ControlPanel old) {
    super.didUpdateWidget(old);
    if (old.device.ip != widget.device.ip) _notes.text = widget.device.notes ?? '';
  }

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.device;
    final diag = widget.diag;
    final networkId = ref.watch(scanControllerProvider.select((s) => s.networkId));
    // Known is a server flag, so only for MACs on a network with an agent.
    final canMarkKnown = d.mac != null &&
        networkId != null &&
        ref.watch(linkedRemoteIdProvider(networkId)).value != null;
    return PdPanel(
      title: 'Tactical node control',
      icon: Icons.bolt,
      trailing: diag.wolSentAt == null ? null : const PdChip('MAGIC PACKET SENT', tone: PdTone.live),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Wake-on-LAN', style: PdText.labelLg),
                    Text(
                      d.mac == null
                          ? 'Needs the MAC address (agent)'
                          : 'Target ${widget.broadcast ?? '255.255.255.255'}:9',
                      style: PdText.code.copyWith(color: PingDuckColors.inkSecondary),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: 130,
                child: PdButton(
                  label: 'Send WOL',
                  icon: Icons.power_settings_new,
                  style: PdButtonStyle.primary,
                  height: 36,
                  onPressed: d.mac == null
                      ? null
                      : () => ref.read(diagnosticsProvider(d.ip).notifier).wake(d.mac!, broadcast: widget.broadcast),
                ),
              ),
            ],
          ),
          if (canMarkKnown) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Known device', style: PdText.labelLg),
                      Text('Known devices never raise new-device alerts', style: PdText.bodySm),
                    ],
                  ),
                ),
                Switch(
                  key: const Key('known_switch'),
                  value: d.isKnown,
                  onChanged: (known) async {
                    final messenger = ScaffoldMessenger.of(context);
                    try {
                      await ref.read(supabaseSyncProvider.notifier).setKnown(networkId, d.mac!, known);
                    } catch (_) {
                      messenger.showSnackBar(
                        const SnackBar(content: Text('Couldn’t reach PingDuck’s servers. Try again.')),
                      );
                    }
                  },
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _notes,
            minLines: 1,
            maxLines: 4,
            style: PdText.bodyMd,
            decoration: InputDecoration(
              labelText: 'NOTES',
              labelStyle: PdText.labelMd,
              hintText: 'Rack, owner, anything worth remembering',
              hintStyle: PdText.bodySm.copyWith(color: PingDuckColors.inkMuted),
            ),
            onSubmitted: (v) => ref.read(scanControllerProvider.notifier).setNotes(d.ip, v),
            onTapOutside: (_) {
              FocusScope.of(context).unfocus();
              if (_notes.text != (d.notes ?? '')) ref.read(scanControllerProvider.notifier).setNotes(d.ip, _notes.text);
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PdButton(
                  label: 'Copy JSON',
                  icon: Icons.data_object,
                  onPressed: () async {
                    await Clipboard.setData(ClipboardData(text: _json(d, diag)));
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device JSON copied')));
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PdButton(
                  label: 'Forget',
                  icon: Icons.delete_outline,
                  style: PdButtonStyle.destructive,
                  onPressed: () async {
                    ref.read(selectedDeviceProvider.notifier).select(null);
                    await ref.read(scanControllerProvider.notifier).forget(d.ip);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _json(DiscoveredDevice d, DiagnosticsState diag) => const JsonEncoder.withIndent('  ').convert({
    'ip': d.ip,
    'mac': d.mac,
    'name': d.displayName,
    'hostname': d.hostname,
    'vendor': d.vendor,
    'model': d.model,
    'services': d.services,
    'sources': [for (final s in d.sources) s.name],
    'online': d.isOnline,
    'rtt_ms': d.rttMs,
    'rtt_history_ms': d.rttHistory,
    'first_seen': d.firstSeen?.toIso8601String(),
    'last_seen': d.lastSeen?.toIso8601String(),
    if (diag.portScan == PortScanState.done) 'open_tcp_ports': (diag.openPorts.toList()..sort()),
    if (d.notes != null) 'notes': d.notes,
  });
}
