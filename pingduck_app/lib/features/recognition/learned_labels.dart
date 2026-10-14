import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../scanner/application/scan_controller.dart';
import '../scanner/domain/device_label.dart';

/// Labels the user taught, by device fingerprint (fingerprint.dart).
/// Invalidated whenever a label is saved or the inventory is cleared.
final learnedLabelsProvider = FutureProvider<Map<String, DeviceLabel>>(
  (ref) => ref.watch(localStoreProvider).learned(),
);
