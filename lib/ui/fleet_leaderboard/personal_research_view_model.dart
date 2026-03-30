/// ViewModel for personal research data.
///
/// Exposes providers used by [PersonalResearchCard] and [PersonalResearchMiniCard].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/personal_research.dart';
import '../../data/services/personal_research_service.dart';

/// Resolves the signed-in user's first robot RRN from Firestore.
/// Returns null when not signed in or no robots registered.
final userRrnProvider = FutureProvider.autoDispose<String?>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  final snap = await FirebaseFirestore.instance
      .collection('robots')
      .where('firebase_uid', isEqualTo: uid)
      .limit(1)
      .get();
  if (snap.docs.isEmpty) return null;
  return snap.docs.first.id;
});

/// Fetches the personal research summary for the signed-in user's first robot.
final personalResearchProvider =
    FutureProvider.autoDispose<PersonalResearchSummary?>((ref) async {
  final rrn = await ref.watch(userRrnProvider.future);
  if (rrn == null) return null;
  return PersonalResearchService().getSummary(rrn);
});

/// Family variant scoped to a specific RRN (used by robot detail screen).
/// Reads from Firestore stream (robots/{rrn}/telemetry/research).
final personalResearchRrnProvider =
    StreamProvider.autoDispose.family<PersonalResearchSummary?, String>(
  (ref, rrn) => PersonalResearchService().summaryStream(rrn),
);
