/// Abstract contract for all robot data operations.
///
/// Concrete implementations:
///   - [FirestoreRobotService] — production, reads from Firebase
///   - MockRobotRepository   — testing / offline development
///
/// Depend on [RobotRepository], never on the concrete class.
/// The DI binding is in [robotRepositoryProvider].
library;

import '../models/command.dart';
import '../models/robot.dart';
import '../models/task_doc.dart';

export '../models/command.dart';
export '../models/robot.dart';
export '../models/task_doc.dart';

abstract class RobotRepository {
  // ── Fleet ──────────────────────────────────────────────────────────────────

  /// Live stream of all robots owned by [uid].
  Stream<List<Robot>> watchFleet(String uid);

  /// One-shot fetch of a single robot by [rrn].
  Future<Robot?> getRobot(String rrn);

  /// Live stream of a single robot's state.
  Stream<Robot?> watchRobot(String rrn);

  // ── Commands ───────────────────────────────────────────────────────────────

  /// Enqueue a command via Cloud Functions (enforces R2RAM + rate limiting).
  /// Returns the new command ID.
  ///
  /// [mediaChunks] — optional list of media attachments; each map must have
  /// `mime_type`, `data` (base64), and optionally `description`.
  Future<String> sendCommand({
    required String rrn,
    required String instruction,
    required CommandScope scope,
    String? reason,
    List<Map<String, dynamic>>? mediaChunks,
  });

  /// Live stream of command history for [rrn] (most recent first).
  Stream<List<RobotCommand>> watchCommands(String rrn, {int limit = 50});

  /// Live stream of a single command's execution status.
  Stream<RobotCommand?> watchCommand(String rrn, String cmdId);

  /// Send ESTOP — bypasses rate limiting in Cloud Functions.
  /// ESTOP must NEVER be rate-limited (Protocol 66 §4.1).
  Future<String> sendEstop(String rrn, {String reason = 'manual estop'});

  /// Send RESUME after ESTOP.
  Future<String> sendResume(String rrn);

  // ── Alerts ─────────────────────────────────────────────────────────────────

  /// Live stream of recent alerts (ESTOP events, faults) for [rrn].
  Stream<List<Map<String, dynamic>>> watchAlerts(String rrn, {int limit = 20});

  // ── Tasks ──────────────────────────────────────────────────────────────────

  /// Live stream of a pick-and-place task doc.
  Stream<TaskDoc?> watchTask(String rrn, String taskId);

  /// Confirm a pending task — writes confirmed=true to Firestore.
  Future<void> confirmTask(String rrn, String taskId);

  /// Update the task_execution setting for [rrn]: 'ask' | 'automatic'.
  Future<void> updateTaskExecution(String rrn, String value);
}
