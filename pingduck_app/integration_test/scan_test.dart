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
import 'package:pingduck_app/services/local_storage.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('tapping Scan streams real LAN devices into the list', (tester) async {
    // Same wiring as main(): the real cache, restored before the first frame.
    final store = LocalStore();
    final restored = await restoreLastScan(store);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(restored),
      ],
      child: const PingDuckApp(),
    ));
    // On a cold start the window may not have a size yet; taps would miss.
    for (var i = 0; i < 50 && tester.view.physicalSize.isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    // No pumpAndSettle here: the radar animates for the whole scan, so it
    // would wait the scan out and the streaming check below would be moot.
    await tester.pump(const Duration(milliseconds: 100));
    // Fresh installs land on onboarding; returning installs scan on launch.
    final start = find.text('START FIRST SCAN');
    if (start.evaluate().isNotEmpty) {
      await tester.ensureVisible(start);
      await tester.tap(start);
    }
    await tester.pump();

    final container = ProviderScope.containerOf(tester.element(find.byType(Scaffold).first));
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
    expect(find.text('RESCAN'), findsOneWidget);
  });
}
