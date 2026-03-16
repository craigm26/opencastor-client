/// Abstract contract for robot-to-robot consent (R2RAM) operations.
///
/// Concrete implementation: [FirestoreConsentService].
/// See RCAN spec §7 (R2RAM — Robot-to-Robot Access Management).
library;

import '../models/consent_request.dart';

export '../models/consent_request.dart';

abstract class ConsentRepository {
  // ── Incoming requests (owner approves / denies) ────────────────────────────

  /// Live stream of pending consent requests for [rrn].
  Stream<List<ConsentRequest>> watchPendingRequests(String rrn);

  /// Live stream of all consent requests (history view).
  Stream<List<ConsentRequest>> watchAllRequests(String rrn);

  /// Approve a consent request, granting [grantedScopes] for [durationHours].
  Future<void> approve({
    required String rrn,
    required String requestId,
    required List<String> grantedScopes,
    int durationHours = 24,
  });

  /// Deny a consent request.
  Future<void> deny({required String rrn, required String requestId});

  // ── Outbound requests (request access to another robot) ───────────────────

  /// Request access to another robot (initiates R2RAM consent flow).
  Future<Map<String, String>> requestAccess({
    required String targetRrn,
    required String sourceRrn,
    required String sourceOwner,
    required String sourceRuri,
    required List<String> requestedScopes,
    required String reason,
    int durationHours = 24,
  });

  // ── Established peers ──────────────────────────────────────────────────────

  /// Live stream of approved consent peers for [rrn].
  Stream<List<Map<String, dynamic>>> watchPeers(String rrn);

  /// Revoke an existing peer consent.
  Future<void> revoke({required String rrn, required String peerOwner});

  /// Count pending consent requests across all [rrns] owned by this user.
  Future<int> pendingRequestCount(List<String> rrns);
}
