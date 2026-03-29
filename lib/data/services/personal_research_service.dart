/// PersonalResearchService — reads research runs from Firestore subcollection
/// and triggers runs via robots/{rrn}/commands (same pattern as contribute toggle).
///
/// Cloud Functions relay cannot reach local-network robots, so we write commands
/// directly to Firestore and read results from the subcollection.
library;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/personal_research.dart';

class PersonalResearchService {
  static final _db = FirebaseFirestore.instance;

  /// Fetches the personal research summary for [rrn] from Firestore.
  ///
  /// Reads from robots/{rrn}/telemetry/research (pushed by bridge).
  /// Returns null if no data is available yet.
  Future<PersonalResearchSummary?> getSummary(String rrn) async {
    if (rrn.isEmpty) return null;
    try {
      final doc = await _db
          .collection('robots')
          .doc(rrn)
          .collection('telemetry')
          .doc('research')
          .get();
      if (!doc.exists || doc.data() == null) return null;
      return PersonalResearchSummary.fromJson(doc.data()!);
    } catch (_) {
      return null;
    }
  }

  /// Stream version — live updates from Firestore.
  Stream<PersonalResearchSummary?> summaryStream(String rrn) {
    if (rrn.isEmpty) return const Stream.empty();
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('telemetry')
        .doc('research')
        .snapshots()
        .map((snap) {
      if (!snap.exists || snap.data() == null) return null;
      try {
        return PersonalResearchSummary.fromJson(snap.data()!);
      } catch (_) {
        return null;
      }
    });
  }

  /// Submits [runId] to the community leaderboard via Firestore command.
  Future<bool> submitToCommunity(String rrn, String runId) async {
    if (rrn.isEmpty) return false;
    try {
      await _db.collection('robots').doc(rrn).collection('commands').add({
        'instruction': 'research_submit',
        'scope': 'system',
        'params': {'run_id': runId, 'community': true},
        'status': 'pending',
        'source': 'app',
        'ts': FieldValue.serverTimestamp(),
        'issued_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Triggers a personal OHB-1 research run via Firestore command.
  Future<bool> triggerRun(String rrn) async {
    if (rrn.isEmpty) return false;
    try {
      await _db.collection('robots').doc(rrn).collection('commands').add({
        'instruction': 'research_run',
        'scope': 'system',
        'params': {'personal': true},
        'status': 'pending',
        'source': 'app',
        'ts': FieldValue.serverTimestamp(),
        'issued_at': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
