import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/pingduck_colors.dart';
import '../../../core/theme/pingduck_theme.dart';
import '../../recognition/recognition.dart';
import '../../scanner/application/scan_controller.dart';
import '../../scanner/domain/discovered_device.dart';

/// Lets the user say what a device is. Fields start with what PingDuck
/// shows now, so saving unchanged confirms a guess. RESET goes back to
/// recognition.
Future<void> editDeviceLabel(BuildContext context, WidgetRef ref, DiscoveredDevice d, Recognition shown) async {
  final os = shown.os;
  final brand = TextEditingController(text: shown.brand?.value ?? '');
  final model = TextEditingController(text: shown.model?.value ?? '');
  final system = TextEditingController(text: os == null ? '' : [os.name, ?os.version].join(' '));
  final label = await showDialog<DeviceLabel>(
    context: context,
    builder: (context) {
      DeviceLabel typed() => DeviceLabel.clean(brand: brand.text, model: model.text, os: system.text);
      return AlertDialog(
        title: Text('WHAT IS ${d.ip}?', style: PdText.labelLg),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: brand,
                autofocus: true,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Brand', hintText: 'Lenovo'),
              ),
              TextField(
                controller: model,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Model', hintText: 'ThinkCentre M70q'),
              ),
              TextField(
                controller: system,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Operating system', hintText: 'Windows 11'),
                onSubmitted: (_) => Navigator.pop(context, typed()),
              ),
              const SizedBox(height: 12),
              Text(
                'Stays on this phone. Devices that look the same get your answer as a likely guess.',
                style: PdText.bodySm.copyWith(color: PingDuckColors.inkSecondary),
              ),
            ],
          ),
        ),
        actions: [
          if (d.label != null)
            TextButton(onPressed: () => Navigator.pop(context, const DeviceLabel()), child: const Text('RESET')),
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('CANCEL')),
          TextButton(onPressed: () => Navigator.pop(context, typed()), child: const Text('SAVE')),
        ],
      );
    },
  );
  if (label != null) await ref.read(scanControllerProvider.notifier).setLabel(d.ip, label);
}
