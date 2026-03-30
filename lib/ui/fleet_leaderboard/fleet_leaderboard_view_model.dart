/// ViewModel for the Fleet Leaderboard screen.
///
/// Exposes [researchStatusProvider] — fetches /api/research/status via
/// the `robotApiGet` Cloud Function.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Fetches research status (explored %, champion score) from
/// `/api/research/status` via `robotApiGet`.
final researchStatusProvider =
    FutureProvider.autoDispose<Map<String, dynamic>>((ref) async {
  try {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {};
    final snap = await FirebaseFirestore.instance
        .collection('robots')
        .where('firebase_uid', isEqualTo: uid)
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return {};
    final rrn = snap.docs.first.id;
    final callable = FirebaseFunctions.instance.httpsCallable(
      'robotApiGet',
      options: HttpsCallableOptions(timeout: const Duration(seconds: 8)),
    );
    final result = await callable.call(<String, dynamic>{
      'rrn': rrn,
      'path': '/api/research/status',
    });
    final data = result.data;
    if (data is Map) return Map<String, dynamic>.from(data);
  } catch (_) {}
  return {};
});
