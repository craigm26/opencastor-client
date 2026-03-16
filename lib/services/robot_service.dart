import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../models/robot.dart';
import '../models/command.dart';

class RobotService {
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  RobotService({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instance;

  // -------------------------------------------------------------------------
  // Fleet queries
  // -------------------------------------------------------------------------

  /// Stream all robots owned by [uid].
  Stream<List<Robot>> watchFleet(String uid) {
    return _db
        .collection('robots')
        .where('firebase_uid', isEqualTo: uid)
        .snapshots()
        .map((snap) => snap.docs.map(Robot.fromDoc).toList()
          ..sort((a, b) => a.name.compareTo(b.name)));
  }

  /// One-time fetch of a single robot.
  Future<Robot?> getRobot(String rrn) async {
    final doc = await _db.collection('robots').doc(rrn).get();
    return doc.exists ? Robot.fromDoc(doc) : null;
  }

  /// Stream a single robot's live state.
  Stream<Robot?> watchRobot(String rrn) {
    return _db.collection('robots').doc(rrn).snapshots().map(
          (snap) => snap.exists ? Robot.fromDoc(snap) : null,
        );
  }

  // -------------------------------------------------------------------------
  // Command queue
  // -------------------------------------------------------------------------

  /// Send a command via Cloud Function (enforces R2RAM + rate limiting).
  Future<String> sendCommand({
    required String rrn,
    required String instruction,
    required CommandScope scope,
    String? reason,
  }) async {
    final callable = _fn.httpsCallable('sendCommand');
    final result = await callable.call({
      'rrn': rrn,
      'instruction': instruction,
      'scope': scope.name,
      if (reason != null) 'reason': reason,
    });
    return result.data['cmd_id'] as String;
  }

  /// Stream command history for a robot (most recent first).
  Stream<List<RobotCommand>> watchCommands(String rrn, {int limit = 50}) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('commands')
        .orderBy('issued_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs.map(RobotCommand.fromDoc).toList());
  }

  /// Poll a single command's status.
  Stream<RobotCommand?> watchCommand(String rrn, String cmdId) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('commands')
        .doc(cmdId)
        .snapshots()
        .map((snap) => snap.exists ? RobotCommand.fromDoc(snap) : null);
  }

  /// Send ESTOP — bypasses rate limiting in Cloud Functions.
  Future<String> sendEstop(String rrn, {String reason = 'manual estop'}) {
    return sendCommand(
      rrn: rrn,
      instruction: 'estop',
      scope: CommandScope.safety,
      reason: reason,
    );
  }

  /// Send RESUME.
  Future<String> sendResume(String rrn) {
    return sendCommand(
      rrn: rrn,
      instruction: 'resume',
      scope: CommandScope.safety,
    );
  }

  // -------------------------------------------------------------------------
  // Alerts
  // -------------------------------------------------------------------------

  /// Stream recent alerts (ESTOP, faults, etc.) for a robot.
  Stream<List<Map<String, dynamic>>> watchAlerts(String rrn, {int limit = 20}) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('alerts')
        .orderBy('fired_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => {'id': d.id, ...d.data()})
            .toList());
  }
}
