// Phase 3 exit check on a real device: cached devices appear on the first
// frame after launch, and a live scan animates the radar without jank.
//
//   flutter build apk --profile -t integration_test/perf_test.dart
//   (install, launch, then read "PERF" lines from logcat)
//
// Run it after at least one normal scan, so the cache has a network to show.
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show Scrollable, debugPrint;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:pingduck_app/features/scanner/application/scan_controller.dart';
import 'package:pingduck_app/main.dart';
import 'package:pingduck_app/services/local_storage.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  // Real frame scheduling, so timings reflect the device, not the test clock.
  binding.framePolicy = LiveTestWidgetsFlutterBindingFramePolicy.fullyLive;

  testWidgets('cold start shows the cache; a scan stays smooth', (tester) async {
    final launch = Stopwatch()..start();
    final store = LocalStore();
    final restored = await restoreLastScan(store);
    final restoreMs = launch.elapsedMilliseconds;

    final timings = <FrameTiming>[];
    void collect(List<FrameTiming> t) => timings.addAll(t);
    SchedulerBinding.instance.addTimingsCallback(collect);

    await tester.pumpWidget(ProviderScope(
      overrides: [
        localStoreProvider.overrideWithValue(store),
        restoredScanProvider.overrideWithValue(restored),
      ],
      child: const PingDuckApp(),
    ));
    final firstFrameMs = launch.elapsedMilliseconds;
    final container = ProviderScope.containerOf(tester.element(find.byType(PingDuckApp)));
    final cachedOnFirstFrame = container.read(scanControllerProvider).devices.length;

    // Returning users get a scan on launch; let it run with live frames.
    final scanWatch = Stopwatch()..start();
    while (!container.read(scanControllerProvider).isScanning && scanWatch.elapsed.inSeconds < 5) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    while (container.read(scanControllerProvider).isScanning && scanWatch.elapsed.inSeconds < 30) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    final scanMs = scanWatch.elapsedMilliseconds;
    // Let the last pulses finish, then scroll the ledger to exercise the list.
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.fling(find.byType(Scrollable).first, const Offset(0, -2000), 3000);
    for (var i = 0; i < 90; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    SchedulerBinding.instance.removeTimingsCallback(collect);

    final refresh = PlatformDispatcher.instance.displays.first.refreshRate;
    final budgetMs = 1000 / refresh;
    List<double> ms(Duration Function(FrameTiming) f) => [for (final t in timings) f(t).inMicroseconds / 1000]..sort();
    double pct(List<double> v, double p) => v.isEmpty ? 0 : v[math.min(v.length - 1, (v.length * p).floor())];
    final build = ms((t) => t.buildDuration);
    final raster = ms((t) => t.rasterDuration);
    final total = ms((t) => t.totalSpan);
    final slow = total.where((v) => v > budgetMs).length;
    final janky = total.where((v) => v > 16.7).length;

    String f(double v) => v.toStringAsFixed(1);
    debugPrint('PERF cache: $cachedOnFirstFrame devices on first frame; restore ${restoreMs}ms, first frame ${firstFrameMs}ms');
    debugPrint('PERF scan: ${container.read(scanControllerProvider).onlineCount} online in ${scanMs}ms');
    debugPrint('PERF frames: ${timings.length} at ${refresh.toStringAsFixed(0)} Hz (budget ${f(budgetMs)}ms)');
    debugPrint('PERF build ms p50 ${f(pct(build, .5))} p90 ${f(pct(build, .9))} p99 ${f(pct(build, .99))}');
    debugPrint('PERF raster ms p50 ${f(pct(raster, .5))} p90 ${f(pct(raster, .9))} p99 ${f(pct(raster, .99))}');
    debugPrint('PERF over budget: $slow (${f(100 * slow / math.max(1, timings.length))}%); over 16.7ms: $janky');

    expect(cachedOnFirstFrame, greaterThan(0), reason: 'run one normal scan first so the cache has devices');
    expect(firstFrameMs, lessThan(1000));
  });
}
