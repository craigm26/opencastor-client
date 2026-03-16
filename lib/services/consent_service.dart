import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/consent_request.dart';

class ConsentService {
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  ConsentService({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instance;

  // -------------------------------------------------------------------------
  // Incoming consent requests (owner must approve/deny)
  // -------------------------------------------------------------------------

  /// Stream pending consent requests for a robot.
  Stream<List<ConsentRequest>> watchPendingRequests(String rrn) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('consent_requests')
        .where('status', isEqualTo: 'pending')
        .orderBy('created_at', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(ConsentRequest.fromDoc).toList());
  }

  /// Stream all consent requests (for history view).
  Stream<List<ConsentRequest>> watchAllRequests(String rrn) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('consent_requests')
        .orderBy('created_at', descending: true)
        .limit(50)
        .snapshots()
        .map((snap) => snap.docs.map(ConsentRequest.fromDoc).toList());
  }

  /// Approve a consent request.
  Future<void> approve({
    required String rrn,
    required String requestId,
    required List<String> grantedScopes,
    int durationHours = 24,
  }) async {
    final callable = _fn.httpsCallable('resolveConsent');
    await callable.call({
      'rrn': rrn,
      'consent_request_id': requestId,
      'decision': 'approve',
      'granted_scopes': grantedScopes,
      'duration_hours': durationHours,
    });
  }

  /// Deny a consent request.
  Future<void> deny({required String rrn, required String requestId}) async {
    final callable = _fn.httpsCallable('resolveConsent');
    await callable.call({
      'rrn': rrn,
      'consent_request_id': requestId,
      'decision': 'deny',
    });
  }

  // -------------------------------------------------------------------------
  // Outbound consent (requesting access to another robot)
  // -------------------------------------------------------------------------

  /// Request access to another robot (robot-to-robot consent initiation).
  Future<Map<String, String>> requestAccess({
    required String targetRrn,
    required String sourceRrn,
    required String sourceOwner,
    required String sourceRuri,
    required List<String> requestedScopes,
    required String reason,
    int durationHours = 24,
  }) async {
    final callable = _fn.httpsCallable('requestConsent');
    final result = await callable.call({
      'target_rrn': targetRrn,
      'source_rrn': sourceRrn,
      'source_owner': sourceOwner,
      'source_ruri': sourceRuri,
      'requested_scopes': requestedScopes,
      'reason': reason,
      'duration_hours': durationHours,
    });
    return Map<String, String>.from(result.data as Map);
  }

  // -------------------------------------------------------------------------
  // Established peer relationships
  // -------------------------------------------------------------------------

  /// Stream established consent peers for a robot.
  Stream<List<Map<String, dynamic>>> watchPeers(String rrn) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('consent_peers')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }

  /// Revoke a peer consent.
  Future<void> revoke({required String rrn, required String peerOwner}) async {
    final callable = _fn.httpsCallable('revokeConsent');
    await callable.call({'rrn': rrn, 'peer_owner': peerOwner});
  }

  /// Count pending consent requests across all robots owned by [uid].
  Future<int> pendingRequestCount(List<String> rrns) async {
    int total = 0;
    for (final rrn in rrns) {
      final snap = await _db
          .collection('robots')
          .doc(rrn)
          .collection('consent_requests')
          .where('status', isEqualTo: 'pending')
          .count()
          .get();
      total += snap.count ?? 0;
    }
    return total;
  }
}
