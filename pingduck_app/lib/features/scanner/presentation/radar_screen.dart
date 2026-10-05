import 'package:flutter/material.dart';

import '../../../core/theme/pingduck_colors.dart';

/// The main "Cortex Map" / Radar view. Phase 3 replaces this placeholder with
/// the live device inventory driven by the scanner controller.
class RadarScreen extends StatelessWidget {
  const RadarScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'PingDuck',
          style: text.titleLarge?.copyWith(
            color: PingDuckColors.duckYellow,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.radar, size: 96, color: PingDuckColors.duckYellow),
            const SizedBox(height: 16),
            Text('Quack. Radar coming online soon.', style: text.titleMedium),
            const SizedBox(height: 4),
            Text(
              'The scanning engine is wired up in Phase 2.',
              style: text.bodyMedium?.copyWith(color: PingDuckColors.textMuted),
            ),
          ],
        ),
      ),
    );
  }
}
