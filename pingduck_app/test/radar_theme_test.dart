import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pingduck_app/core/theme/pingduck_colors.dart';
import 'package:pingduck_app/core/theme/pingduck_theme.dart';
import 'package:pingduck_app/features/scanner/domain/discovered_device.dart';
import 'package:pingduck_app/features/scanner/presentation/radar_scope.dart';

void main() {
  final onlineDevice = DiscoveredDevice(
    ip: '192.168.1.100',
    mac: '00:11:22:33:44:55',
    isOnline: true,
    rttMs: 15,
  );
  final offlineDevice = DiscoveredDevice(
    ip: '192.168.1.101',
    mac: '00:11:22:33:44:56',
    isOnline: false,
    rttHistory: const [50],
  );

  testWidgets('RadarScope paints in light mode', (tester) async {
    PingDuckColors.isDark = false;
    await tester.pumpWidget(
      MaterialApp(
        theme: PingDuckTheme.light(),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: RadarScope(
                devices: [onlineDevice, offlineDevice],
                scanning: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RadarScope), findsOneWidget);
  });

  testWidgets('RadarScope paints in dark mode without error', (tester) async {
    PingDuckColors.isDark = true;
    await tester.pumpWidget(
      MaterialApp(
        theme: PingDuckTheme.dark(),
        themeMode: ThemeMode.dark,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 400,
              height: 400,
              child: RadarScope(
                devices: [onlineDevice, offlineDevice],
                scanning: false,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(RadarScope), findsOneWidget);
    PingDuckColors.isDark = false;
  });
}
