/// ViewModel for the Alerts screen.
///
/// Exposes [alertsProvider] — a per-robot stream of ESTOP events and faults.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;

/// Live stream of alerts for [rrn] (most recent 30 entries).
final alertsProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, rrn) {
  return ref
      .read(robotRepositoryProvider)
      .watchAlerts(rrn, limit: 30);
});
