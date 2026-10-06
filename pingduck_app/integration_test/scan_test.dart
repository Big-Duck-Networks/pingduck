// End-to-end check of Phase 2's exit criterion on a real device on the LAN:
// tapping Scan streams the devices the native core finds into the UI.
//
//   flutter test integration_test -d <device-id>
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/main.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping Scan streams real LAN devices into the list', (tester) async {
    await tester.pumpWidget(const ProviderScope(child: PingDuckApp()));
    // On a cold start the window may not have a size yet; taps would miss.
    for (var i = 0; i < 50 && tester.view.physicalSize.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pumpAndSettle();
    await tester.tap(find.text('Scan'));
    await tester.pump();
    expect(find.text('Stop'), findsOneWidget);

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold)));
    final sw = Stopwatch()..start();
    var firstDeviceAt = Duration.zero;
    while (container.read(scanControllerProvider).isScanning && sw.elapsed < const Duration(seconds: 20)) {
      await tester.pump(const Duration(milliseconds: 100));
      if (firstDeviceAt == Duration.zero && container.read(scanControllerProvider).devices.isNotEmpty) {
        firstDeviceAt = sw.elapsed;
      }
    }
    await tester.pumpAndSettle();

    final state = container.read(scanControllerProvider);
    final devices = state.sortedDevices;
    debugPrint('scan: ${state.phase}, ${devices.length} devices in ${sw.elapsedMilliseconds} ms '
        '(first after ${firstDeviceAt.inMilliseconds} ms)');
    for (final d in devices) {
      debugPrint('  ${d.ip.padRight(15)} ${d.mac ?? '-'}  ${d.displayName}  [${d.vendor ?? ''}] '
          '${d.sources.map((s) => s.name).join('+')}');
    }

    expect(state.phase, ScanPhase.done);
    expect(devices.length, greaterThan(3));
    expect(firstDeviceAt, lessThan(const Duration(seconds: 3)));  // streams, not batch-at-end
    expect(devices.where((d) => d.vendor != null), isNotEmpty);  // OUI asset loaded
    expect(find.text('Scan'), findsOneWidget);
    expect(find.byType(ListTile), findsWidgets);
  });
}
