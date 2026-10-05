import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/theme/pingduck_theme.dart';
import 'features/scanner/presentation/radar_screen.dart';

void main() {
  runApp(const ProviderScope(child: PingDuckApp()));
}

class PingDuckApp extends StatelessWidget {
  const PingDuckApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'PingDuck',
      debugShowCheckedModeBanner: false,
      theme: PingDuckTheme.dark(),
      home: const RadarScreen(),
    );
  }
}
