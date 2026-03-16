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

export '../models/command.dart';
export '../models/robot.dart';

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
  Future<String> sendCommand({
    required String rrn,
    required String instruction,
    required CommandScope scope,
    String? reason,
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
}
