import 'package:cloud_firestore/cloud_firestore.dart';

enum ConsentRequestStatus { pending, approved, denied, expired, revoked }

class ConsentRequest {
  final String id;
  final String fromRrn;
  final String fromOwner;
  final String fromRuri;
  final List<String> requestedScopes;
  final String reason;
  final int durationHours;
  final ConsentRequestStatus status;
  final DateTime createdAt;
  final DateTime? resolvedAt;
  final List<String> grantedScopes;
  final String? consentId;
  final DateTime? expiresAt;

  const ConsentRequest({
    required this.id,
    required this.fromRrn,
    required this.fromOwner,
    required this.fromRuri,
    required this.requestedScopes,
    required this.reason,
    required this.durationHours,
    required this.status,
    required this.createdAt,
    this.resolvedAt,
    required this.grantedScopes,
    this.consentId,
    this.expiresAt,
  });

  factory ConsentRequest.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return ConsentRequest(
      id: doc.id,
      fromRrn: m['from_rrn'] as String? ?? '',
      fromOwner: m['from_owner'] as String? ?? '',
      fromRuri: m['from_ruri'] as String? ?? '',
      requestedScopes: List<String>.from(m['requested_scopes'] as List? ?? []),
      reason: m['reason'] as String? ?? '',
      durationHours: m['duration_hours'] as int? ?? 24,
      status: _parseStatus(m['status'] as String? ?? 'pending'),
      createdAt: DateTime.parse(m['created_at'] as String),
      resolvedAt: m['resolved_at'] != null
          ? DateTime.parse(m['resolved_at'] as String)
          : null,
      grantedScopes: List<String>.from(m['granted_scopes'] as List? ?? []),
      consentId: m['consent_id'] as String?,
      expiresAt: m['expires_at'] != null
          ? DateTime.parse(m['expires_at'] as String)
          : null,
    );
  }

  bool get isPending => status == ConsentRequestStatus.pending;

  static ConsentRequestStatus _parseStatus(String s) =>
      ConsentRequestStatus.values.firstWhere((e) => e.name == s,
          orElse: () => ConsentRequestStatus.pending);
}
