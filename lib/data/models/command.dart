import 'package:cloud_firestore/cloud_firestore.dart';

enum CommandScope { discover, status, chat, control, safety, transparency }

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
  /// e.g. "human via OpenCastor app" | "service:opencastor-cloud-relay" | "robot:<rrn>"
  final String? senderType;

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
  });

  factory RobotCommand.fromDoc(DocumentSnapshot doc) {
    final m = doc.data() as Map<String, dynamic>;
    return RobotCommand(
      id: doc.id,
      instruction: m['instruction'] as String? ?? '',
      scope: _parseScope(m['scope'] as String? ?? 'chat'),
      issuedByUid: m['issued_by_uid'] as String? ?? '',
      issuedAt: m['issued_at'] != null
          ? DateTime.parse(m['issued_at'] as String)
          : DateTime.now(),
      status: _parseStatus(m['status'] as String? ?? 'pending'),
      result: m['result'] as Map<String, dynamic>?,
      error: m['error'] as String?,
      completedAt: m['completed_at'] != null
          ? DateTime.parse(m['completed_at'] as String)
          : null,
      // GAP-08: parse sender_type from audit field; default to human app sender
      senderType: m['sender_type'] as String? ?? 'human via OpenCastor app',
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
}
