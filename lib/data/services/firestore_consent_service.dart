import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../repositories/consent_repository.dart';

/// Firestore + Cloud Functions implementation of [ConsentRepository].
///
/// All consent decisions go through Cloud Functions to enforce R2RAM §7.
class FirestoreConsentService implements ConsentRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  FirestoreConsentService({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instance;

  @override
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

  @override
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

  @override
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

  @override
  Future<void> deny({required String rrn, required String requestId}) async {
    final callable = _fn.httpsCallable('resolveConsent');
    await callable.call({
      'rrn': rrn,
      'consent_request_id': requestId,
      'decision': 'deny',
    });
  }

  @override
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

  @override
  Stream<List<Map<String, dynamic>>> watchPeers(String rrn) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('consent_peers')
        .where('status', isEqualTo: 'approved')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  @override
  Future<void> revoke({required String rrn, required String peerOwner}) async {
    final callable = _fn.httpsCallable('revokeConsent');
    await callable.call({'rrn': rrn, 'peer_owner': peerOwner});
  }

  @override
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
