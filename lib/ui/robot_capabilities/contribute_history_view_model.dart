/// ViewModel for the Contribution History view.
///
/// Exposes [contributeHistoryProvider] — a FutureProvider that reads the
/// last 90 days of daily contribution records from Firestore.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fetches contribution history (last 90 days) for [rrn].
/// Reads from `robots/{rrn}/telemetry/contribute_history`.
final contributeHistoryProvider =
    FutureProvider.family<List<Map<String, dynamic>>, String>((ref, rrn) async {
  try {
    final doc = await FirebaseFirestore.instance
        .collection('robots')
        .doc(rrn)
        .collection('telemetry')
        .doc('contribute_history')
        .get();
    if (!doc.exists) return [];
    final data = doc.data();
    if (data == null) return [];
    final history = data['history'] as List<dynamic>? ?? [];
    return history.cast<Map<String, dynamic>>();
  } catch (_) {
    return [];
  }
});
