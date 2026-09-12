/// PersonalResearchService — reads research runs from Firestore subcollection
/// and triggers runs through the `sendCommand` Cloud Function callable.
///
/// Reads come straight from Firestore (telemetry is owner-readable). Writes do
/// NOT: queuing a command by writing to robots/{rrn}/commands from the client
/// skips the owner-only check on `system` scope, skips the per-scope rate
/// limit, and leaves the command with no `issued_by_uid`, so nothing can say
/// who asked for it. The callable is the only sanctioned path, and
/// firestore.rules refuses a client-created `system` command outright.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';

import '../models/personal_research.dart';

class PersonalResearchService {
  static final _db = FirebaseFirestore.instance;

  final FirebaseFunctions _fn;

  PersonalResearchService({FirebaseFunctions? fn})
      : _fn = fn ?? FirebaseFunctions.instance;

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

  /// Submits [runId] to the community leaderboard via the sendCommand callable.
  Future<bool> submitToCommunity(String rrn, String runId) async {
    if (rrn.isEmpty) return false;
    try {
      await _fn.httpsCallable('sendCommand').call({
        'rrn': rrn,
        'instruction': 'research_submit',
        'scope': 'system',
        'reason': 'user submitted a research run to the community leaderboard',
        'params': {'run_id': runId, 'community': true},
      });
      return true;
    } catch (_) {
      return false;
    }
  }

  /// Triggers a personal OHB-1 research run via the sendCommand callable.
  Future<bool> triggerRun(String rrn) async {
    if (rrn.isEmpty) return false;
    try {
      await _fn.httpsCallable('sendCommand').call({
        'rrn': rrn,
        'instruction': 'research_run',
        'scope': 'system',
        'reason': 'user started a personal research run',
        'params': {'personal': true},
      });
      return true;
    } catch (_) {
      return false;
    }
  }
}
