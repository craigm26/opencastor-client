import 'package:cloud_firestore/cloud_firestore.dart';

enum CommandScope { discover, status, chat, control, safety, transparency, system }

enum CommandStatus { pending, processing, complete, failed, denied, expired, pendingConsent }

class RobotCommand {
  final String id;
  final String instruction;
  final CommandScope scope;
  final String issuedByUid;
  final DateTime issuedAt;
  final CommandStatus status;
  final Map<String, dynamic>? result;
  final String? error;
  final DateTime? completedAt;

  /// GAP-08: Sender type for audit trail display.
  /// e.g. "human via OpenCastor app" | "service:opencastor-cloud-relay" | "robot:`<rrn>`"
  final String? senderType;

  /// Links this command to a live Firestore task doc for pick-and-place tasks.
  final String? taskId;

  const RobotCommand({
    required this.id,
    required this.instruction,
    required this.scope,
    required this.issuedByUid,
    required this.issuedAt,
    required this.status,
    this.result,
    this.error,
    this.completedAt,
    this.senderType,
    this.taskId,
  });

  factory RobotCommand.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return RobotCommand(
      id: doc.id,
      instruction: m['instruction'] as String? ?? '',
      scope: _parseScope(m['scope'] as String? ?? 'chat'),
      issuedByUid: m['issued_by_uid'] as String? ?? '',
      issuedAt: _parseDateTime(m['issued_at']) ?? DateTime.now(),
      status: _parseStatus(m['status'] as String? ?? 'pending'),
      result: m['result'] is Map ? Map<String, dynamic>.from(m['result'] as Map) : null,
      error: m['error'] as String?,
      completedAt: _parseDateTime(m['completed_at']),
      // GAP-08: parse sender_type from audit field; default to human app sender
      senderType: m['sender_type'] as String? ?? 'human via OpenCastor app',
      taskId: m['task_id'] as String?,
    );
  }

  bool get isComplete => status == CommandStatus.complete;
  bool get isFailed =>
      status == CommandStatus.failed || status == CommandStatus.denied;
  bool get isPending =>
      status == CommandStatus.pending || status == CommandStatus.processing;

  static CommandScope _parseScope(String s) =>
      CommandScope.values.firstWhere((e) => e.name == s, orElse: () => CommandScope.chat);

  static CommandStatus _parseStatus(String s) {
    const map = {
      'pending_consent': CommandStatus.pendingConsent,
    };
    return map[s] ??
        CommandStatus.values.firstWhere((e) => e.name == s,
            orElse: () => CommandStatus.pending);
  }

  /// Safely parse a date field that may be a String ISO-8601, a Firestore
  /// Timestamp/DatetimeWithNanoseconds, or null.
  static DateTime? _parseDateTime(dynamic raw) {
    if (raw == null) return null;
    if (raw is DateTime) return raw;
    if (raw is String) return DateTime.tryParse(raw);
    // Firestore Timestamp / DatetimeWithNanoseconds — both expose .toDate()
    try { return (raw as dynamic).toDate() as DateTime; } catch (_) {}
    return null;
  }
}
