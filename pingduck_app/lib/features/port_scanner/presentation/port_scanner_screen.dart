import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../../core/theme/theme_mode_provider.dart';
import '../../../core/widgets/pd_widgets.dart';
import '../../tools/presentation/tools_screen.dart';
import '../application/port_scanner_controller.dart';
import '../domain/port_scan_models.dart';

const popularTargets = [
  'google.com',
  'facebook.com',
  'amazon.com',
  'bing.com',
  'apple.com',
];

class PortScannerTool extends ConsumerStatefulWidget {
  const PortScannerTool({super.key});

  @override
  ConsumerState<PortScannerTool> createState() => _PortScannerToolState();
}

class _PortScannerToolState extends ConsumerState<PortScannerTool> {
  late final TextEditingController _inputController;
  final FocusNode _focusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    final initial = ref.read(portScannerProvider).targetInput;
    _inputController = TextEditingController(text: initial);
  }

  @override
  void dispose() {
    _inputController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _triggerScan([String? explicitHost]) {
    _focusNode.unfocus();
    final host = explicitHost ?? _inputController.text;
    if (explicitHost != null) {
      _inputController.text = explicitHost;
    }
    ref.read(portScannerProvider.notifier).startScan(host);
  }

  void _openSettings() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => const _PortScanSettingsSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(appThemeModeProvider);
    final theme = Theme.of(context);
    final state = ref.watch(portScannerProvider);
    final ctrl = ref.read(portScannerProvider.notifier);

    // Keep controller synced if state input changes externally (e.g. from chip tap)
    if (state.targetInput != _inputController.text && state.isScanning) {
      _inputController.text = state.targetInput;
    }

    final hasActiveResults = state.status == PortScanStatus.done ||
        state.status == PortScanStatus.failed ||
        state.status == PortScanStatus.cancelled ||
        state.status == PortScanStatus.scanning ||
        state.status == PortScanStatus.resolving;

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      children: [
        const ToolBreadcrumb(Tool.portScanner),
        const SizedBox(height: 8),

        // Header matching reference screenshot
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                'Find open ports',
                style: PdText.headlineMd.copyWith(color: theme.colorScheme.onSurface),
              ),
            ),
            TextButton(
              onPressed: _openSettings,
              style: TextButton.styleFrom(
                foregroundColor: theme.colorScheme.primary,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
              child: Text('SETTINGS', style: PdText.labelLg.copyWith(color: theme.colorScheme.primary)),
            ),
          ],
        ),
        const SizedBox(height: 8),

        Text(
          'Probe a specific target host to detect open TCP ports to determine available services and assess vulnerabilities.',
          style: PdText.bodySm.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),

        // Target Input Field
        Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerLow,
            border: Border.all(color: theme.colorScheme.outline),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _inputController,
                  focusNode: _focusNode,
                  enabled: !state.isScanning,
                  style: PdText.codeLg.copyWith(color: theme.colorScheme.onSurface),
                  decoration: InputDecoration(
                    hintText: 'Enter IP or domain',
                    hintStyle: PdText.bodyMd.copyWith(color: PingDuckColors.inkMuted),
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  autocorrect: false,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.search,
                  onChanged: ctrl.updateInput,
                  onSubmitted: (val) => _triggerScan(val),
                ),
              ),
              if (_inputController.text.isNotEmpty && !state.isScanning)
                IconButton(
                  tooltip: 'Clear input',
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _inputController.clear();
                    ctrl.updateInput('');
                  },
                )
              else if (_inputController.text.isEmpty && !state.isScanning)
                IconButton(
                  tooltip: 'Paste from clipboard',
                  icon: const Icon(Icons.content_paste_outlined, size: 18),
                  onPressed: () async {
                    final data = await Clipboard.getData(Clipboard.kTextPlain);
                    if (data?.text != null && data!.text!.trim().isNotEmpty) {
                      _inputController.text = data.text!.trim();
                      ctrl.updateInput(data.text!.trim());
                    }
                  },
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),

        // Action Button / State
        if (state.isScanning) ...[
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLow,
              border: Border.all(color: PingDuckColors.liveBorder),
            ),
            child: Row(
              children: [
                const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2, color: PingDuckColors.live),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    state.status == PortScanStatus.resolving
                        ? 'Resolving domain DNS…'
                        : 'Probing ${state.scannedPorts.length} ports on ${state.resolvedIp ?? state.activeHost}…',
                    style: PdText.code.copyWith(color: PingDuckColors.live),
                  ),
                ),
                TextButton(
                  onPressed: ctrl.cancelScan,
                  style: TextButton.styleFrom(
                    foregroundColor: PingDuckColors.critical,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  ),
                  child: const Text('CANCEL'),
                ),
              ],
            ),
          ),
        ] else ...[
          PdButton(
            label: 'Find open ports',
            style: PdButtonStyle.primary,
            onPressed: () => _triggerScan(),
          ),
        ],

        if (state.error != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: PingDuckColors.criticalFill,
              border: Border.all(color: PingDuckColors.criticalBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline, size: 16, color: PingDuckColors.critical),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(state.error!, style: PdText.bodySm.copyWith(color: PingDuckColors.critical)),
                ),
              ],
            ),
          ),
        ],

        const SizedBox(height: 20),

        // If results exist and not currently in initial input state, show report
        if (hasActiveResults && state.activeHost != null) ...[
          _ScanResultCard(
            state: state,
            onRescan: () => _triggerScan(state.activeHost),
            onReset: () {
              ctrl.resetToInput();
              _inputController.clear();
            },
          ),
          const SizedBox(height: 24),
        ],

        // Popular Targets Section (Matches Reference Screenshot)
        Text(
          'Popular targets',
          style: PdText.headlineSm.copyWith(color: theme.colorScheme.onSurface),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final target in popularTargets)
              Semantics(
                button: true,
                label: 'Scan $target',
                child: InkWell(
                  onTap: () => _triggerScan(target),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1E293B),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFF334155)),
                    ),
                    child: Text(
                      target,
                      style: PdText.labelMd.copyWith(color: const Color(0xFF60A5FA)),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),

        // Recent Hosts Section (Matches Reference Screenshot)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              'Recent hosts',
              style: PdText.headlineSm.copyWith(color: theme.colorScheme.onSurface),
            ),
            if (state.recentHosts.isNotEmpty)
              TextButton(
                onPressed: ctrl.clearRecentHosts,
                style: TextButton.styleFrom(
                  foregroundColor: PingDuckColors.inkMuted,
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                ),
                child: Text('Clear all', style: PdText.labelSm),
              ),
          ],
        ),
        const SizedBox(height: 8),

        if (state.recentHosts.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Text(
              'There is no recent host or domain to show. If you enter one manually you will find it later in this area.',
              style: PdText.bodySm.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        ] else ...[
          for (final recent in state.recentHosts)
            _RecentHostTile(
              recent: recent,
              onTap: () => _triggerScan(recent.host),
              onDelete: () => ctrl.removeRecentHost(recent.host),
            ),
        ],
        const SizedBox(height: 32),
      ],
    );
  }
}

class _RecentHostTile extends StatelessWidget {
  const _RecentHostTile({
    required this.recent,
    required this.onTap,
    required this.onDelete,
  });

  final RecentPortScanHost recent;
  final VoidCallback onTap;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasOpen = recent.openPortsCount > 0;
    return InkWell(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          border: Border.all(color: theme.colorScheme.outlineVariant),
        ),
        child: Row(
          children: [
            Icon(Icons.history, size: 18, color: PingDuckColors.inkMuted),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    recent.host,
                    style: PdText.codeLg.copyWith(color: theme.colorScheme.onSurface),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (recent.resolvedIp != null && recent.resolvedIp != recent.host) ...[
                    const SizedBox(height: 2),
                    Text(recent.resolvedIp!, style: PdText.code.copyWith(color: PingDuckColors.inkMuted)),
                  ],
                ],
              ),
            ),
            PdChip(
              hasOpen ? '${recent.openPortsCount} open' : 'No open ports',
              tone: hasOpen ? PdTone.live : PdTone.neutral,
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: 'Remove',
              icon: const Icon(Icons.close, size: 16),
              onPressed: onDelete,
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ],
        ),
      ),
    );
  }
}

class _ScanResultCard extends StatelessWidget {
  const _ScanResultCard({
    required this.state,
    required this.onRescan,
    required this.onReset,
  });

  final PortScannerState state;
  final VoidCallback onRescan;
  final VoidCallback onReset;

  void _copyReport(BuildContext context) {
    final buffer = StringBuffer();
    buffer.writeln('PingDuck Port Scan Report');
    buffer.writeln('Target: ${state.activeHost}');
    if (state.resolvedIp != null) buffer.writeln('IP: ${state.resolvedIp}');
    buffer.writeln('Scanned ports: ${state.scannedPorts.length}');
    buffer.writeln('Open ports: ${state.openPorts.length}');
    if (state.scanDuration != null) {
      buffer.writeln('Duration: ${(state.scanDuration!.inMilliseconds / 1000).toStringAsFixed(2)}s');
    }
    buffer.writeln('\n--- Open Services ---');
    if (state.openPorts.isEmpty) {
      buffer.writeln('None');
    } else {
      final sorted = state.openPorts.toList()..sort();
      for (final port in sorted) {
        final info = lookupPortDetails(port);
        buffer.write('${info.port} / ${info.service}');
        if (info.risk != null) buffer.write(' - [RISK: ${info.risk}]');
        buffer.writeln();
      }
    }
    Clipboard.setData(ClipboardData(text: buffer.toString()));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Port scan report copied to clipboard')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final sortedOpen = state.openPorts.toList()..sort();
    final closedCount = state.scannedPorts.length - state.openPorts.length;
    final isDone = state.status == PortScanStatus.done;

    return PdPanel(
      title: 'Scan results: ${state.activeHost}',
      accent: isDone && sortedOpen.isNotEmpty ? PingDuckColors.live : null,
      trailing: PdChip(
        isDone ? '${sortedOpen.length} open / ${state.scannedPorts.length}' : state.status.name.toUpperCase(),
        tone: sortedOpen.isNotEmpty ? PdTone.live : PdTone.neutral,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Target stats
          Row(
            children: [
              if (state.resolvedIp != null)
                Expanded(
                  child: PdField(
                    label: 'Resolved IP',
                    value: state.resolvedIp!,
                  ),
                ),
              if (state.scanDuration != null) ...[
                const SizedBox(width: 8),
                Expanded(
                  child: PdField(
                    label: 'Duration',
                    value: '${(state.scanDuration!.inMilliseconds / 1000).toStringAsFixed(2)}s',
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),

          // Open Ports Section
          if (sortedOpen.isEmpty && isDone) ...[
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                'No open ports detected among the ${state.scannedPorts.length} probed ports.',
                style: PdText.bodySm.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ] else ...[
            for (final port in sortedOpen) ...[
              _PortResultTile(port: port),
              const SizedBox(height: 6),
            ],
          ],

          if (closedCount > 0 && isDone) ...[
            const SizedBox(height: 8),
            Text(
              '$closedCount ports closed or filtered (no response).',
              style: PdText.labelSm.copyWith(color: PingDuckColors.inkMuted),
            ),
          ],
          const SizedBox(height: 16),

          // Actions Row
          Row(
            children: [
              Expanded(
                child: PdButton(
                  label: 'Copy report',
                  icon: Icons.copy,
                  style: PdButtonStyle.secondary,
                  onPressed: () => _copyReport(context),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: PdButton(
                  label: 'Scan again',
                  icon: Icons.refresh,
                  style: PdButtonStyle.secondary,
                  onPressed: onRescan,
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: 'Done / Clear',
                icon: const Icon(Icons.close),
                onPressed: onReset,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PortResultTile extends StatelessWidget {
  const _PortResultTile({required this.port});

  final int port;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final info = lookupPortDetails(port);
    final hasRisk = info.risk != null;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          left: BorderSide(
            color: hasRisk ? PingDuckColors.critical : PingDuckColors.live,
            width: 3,
          ),
          top: BorderSide(color: theme.colorScheme.outlineVariant),
          right: BorderSide(color: theme.colorScheme.outlineVariant),
          bottom: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '${info.port}',
                style: PdText.headlineSm.copyWith(color: theme.colorScheme.onSurface),
              ),
              const SizedBox(width: 8),
              Text(
                info.service,
                style: PdText.labelLg.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              const Spacer(),
              const PdChip('OPEN', tone: PdTone.live),
            ],
          ),
          if (hasRisk) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 14, color: PingDuckColors.critical),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    info.risk!,
                    style: PdText.bodySm.copyWith(color: PingDuckColors.critical),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _PortScanSettingsSheet extends ConsumerStatefulWidget {
  const _PortScanSettingsSheet();

  @override
  ConsumerState<_PortScanSettingsSheet> createState() => _PortScanSettingsSheetState();
}

class _PortScanSettingsSheetState extends ConsumerState<_PortScanSettingsSheet> {
  late PortScanProfile _profile;
  late int _timeout;
  late final TextEditingController _customController;

  @override
  void initState() {
    super.initState();
    final state = ref.read(portScannerProvider);
    _profile = state.profile;
    _timeout = state.timeoutMs;
    _customController = TextEditingController(text: state.customPorts.join(', '));
  }

  @override
  void dispose() {
    _customController.dispose();
    super.dispose();
  }

  void _save() {
    final ctrl = ref.read(portScannerProvider.notifier);
    ctrl.setTimeout(_timeout);
    if (_profile == PortScanProfile.custom) {
      final parsed = _customController.text
          .split(',')
          .map((s) => int.tryParse(s.trim()))
          .whereType<int>()
          .where((p) => p > 0 && p <= 65535)
          .toList();
      ctrl.setProfile(_profile, custom: parsed);
    } else {
      ctrl.setProfile(_profile);
    }
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(top: BorderSide(color: theme.colorScheme.outline)),
      ),
      padding: EdgeInsets.only(
        top: 16,
        left: 16,
        right: 16,
        bottom: 16 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Port Scanner Settings', style: PdText.headlineSm),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.of(context).pop(),
              ),
            ],
          ),
          const SizedBox(height: 16),

          Text('PORT PROFILE', style: PdText.labelMd.copyWith(color: PingDuckColors.inkMuted)),
          const SizedBox(height: 8),
          for (final p in PortScanProfile.values) ...[
            InkWell(
              onTap: () => setState(() => _profile = p),
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _profile == p ? theme.colorScheme.surfaceContainerLow : theme.colorScheme.surface,
                  border: Border.all(
                    color: _profile == p ? PingDuckColors.ink : theme.colorScheme.outlineVariant,
                    width: _profile == p ? 2 : 1,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _profile == p ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                      color: _profile == p ? PingDuckColors.ink : PingDuckColors.inkMuted,
                      size: 20,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(p.label, style: PdText.labelLg.copyWith(color: theme.colorScheme.onSurface)),
                          const SizedBox(height: 2),
                          Text(p.description, style: PdText.bodySm.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],

          if (_profile == PortScanProfile.custom) ...[
            const SizedBox(height: 8),
            TextField(
              controller: _customController,
              decoration: const InputDecoration(
                labelText: 'Custom ports (comma separated)',
                hintText: 'e.g. 80, 443, 8080, 3000',
              ),
              keyboardType: TextInputType.number,
            ),
          ],
          const SizedBox(height: 16),

          Text('CONNECTION TIMEOUT', style: PdText.labelMd.copyWith(color: PingDuckColors.inkMuted)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            children: [
              for (final ms in [500, 800, 1500, 3000])
                ChoiceChip(
                  label: Text('${ms}ms'),
                  selected: _timeout == ms,
                  onSelected: (sel) {
                    if (sel) setState(() => _timeout = ms);
                  },
                ),
            ],
          ),
          const SizedBox(height: 24),

          PdButton(
            label: 'Save & Close',
            style: PdButtonStyle.primary,
            onPressed: _save,
          ),
        ],
      ),
    );
  }
}
