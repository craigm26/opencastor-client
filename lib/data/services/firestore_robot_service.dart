import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/app_logger.dart';
import '../models/command.dart';
import '../models/robot.dart';
import '../models/task_doc.dart';
import '../repositories/robot_repository.dart';

/// Firestore + Cloud Functions implementation of [RobotRepository].
///
/// All write operations go through Cloud Functions to enforce:
///   - R2RAM scope validation
///   - Rate limiting (except ESTOP — never rate-limited)
///   - Consent checks
class FirestoreRobotService implements RobotRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  FirestoreRobotService({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instance;

  @override
  Stream<List<Robot>> watchFleet(String uid) {
    log.d('FirestoreRobotService.watchFleet: uid="$uid"');
    return _db
        .collection('robots')
        .where('firebase_uid', isEqualTo: uid)
        .snapshots()
        .map((snap) {
          log.d('watchFleet snapshot: ${snap.docs.length} docs, fromCache=${snap.metadata.isFromCache}');
          if (snap.docs.isEmpty) {
            log.w('watchFleet: no documents matched firebase_uid="$uid" — check Firestore /robots docs have this uid set');
          }
          return snap.docs.map(Robot.fromDoc).toList()
            ..sort((a, b) => a.name.compareTo(b.name));
        })
        .handleError((e, st) {
          log.e('watchFleet ERROR — uid="$uid"', error: e, stackTrace: st as StackTrace?);
        });
  }

  @override
  Future<Robot?> getRobot(String rrn) async {
    final doc = await _db.collection('robots').doc(rrn).get();
    return doc.exists ? Robot.fromDoc(doc) : null;
  }

  @override
  Stream<Robot?> watchRobot(String rrn) {
    return _db.collection('robots').doc(rrn).snapshots().map(
          (snap) => snap.exists ? Robot.fromDoc(snap) : null,
        );
  }

  @override
  Future<String> sendCommand({
    required String rrn,
    required String instruction,
    required CommandScope scope,
    String? reason,
    List<Map<String, dynamic>>? mediaChunks,
    Map<String, dynamic>? params,
  }) async {
    final callable = _fn.httpsCallable('sendCommand');
    final result = await callable.call({
      'rrn': rrn,
      'instruction': instruction,
      'scope': scope.name,
      if (reason != null) 'reason': reason,
      if (mediaChunks != null) 'media_chunks': mediaChunks,
      if (params != null) 'params': params,
    });
    return result.data['cmd_id'] as String;
  }

  @override
  Stream<List<RobotCommand>> watchCommands(String rrn, {int limit = 50}) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('commands')
        .orderBy('issued_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            // Exclude mission_thread commands — those belong in the Mission screen,
            // not the individual robot chat history.
            .where((doc) {
              final data = doc.data() as Map<String, dynamic>;
              return data['context'] != 'mission_thread';
            })
            .map(RobotCommand.fromDoc)
            .toList());
  }

  @override
  Stream<RobotCommand?> watchCommand(String rrn, String cmdId) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('commands')
        .doc(cmdId)
        .snapshots()
        .map((snap) => snap.exists ? RobotCommand.fromDoc(snap) : null);
  }

  /// Queue an ESTOP command for [rrn] and return its command id.
  ///
  /// OC-M-01 — WHAT THE RETURNED FUTURE MEANS: the command document was
  /// written. That is all. It does NOT mean the cloud bridge read it, that the
  /// bridge dispatched it to the runtime, or that any motion ceased. This is a
  /// Firestore write and nothing more.
  ///
  /// The only stop acknowledgement in this system is a dispatch result: a 2xx
  /// from the robot's own LAN API, or `ack_qos: acknowledged` stamped onto this
  /// command document by the bridge after it dispatched. Callers must show
  /// "queued" until one of those lands, and must never claim motion ceased.
  /// See `ui/shared/estop_feedback.dart`.
  @override
  Future<String> sendEstop(String rrn, {String reason = 'manual estop'}) {
    // ESTOP bypasses all rate limiting — see Cloud Functions relay.ts
    return sendCommand(
      rrn: rrn,
      instruction: 'estop',
      scope: CommandScope.safety,
      reason: reason,
    );
  }

  @override
  Future<String> sendResume(String rrn) {
    return sendCommand(
      rrn: rrn,
      instruction: 'resume',
      scope: CommandScope.safety,
    );
  }

  @override
  Stream<List<Map<String, dynamic>>> watchAlerts(String rrn, {int limit = 20}) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('alerts')
        .orderBy('fired_at', descending: true)
        .limit(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }

  @override
  Stream<TaskDoc?> watchTask(String rrn, String taskId) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('tasks')
        .doc(taskId)
        .snapshots()
        .map((snap) {
      if (!snap.exists) return null;
      return TaskDoc.fromMap(snap.id, snap.data() as Map<String, dynamic>);
    });
  }

  @override
  Future<void> confirmTask(String rrn, String taskId) {
    return _db
        .collection('robots')
        .doc(rrn)
        .collection('tasks')
        .doc(taskId)
        .update({'confirmed': true});
  }

  @override
  Future<void> updateTaskExecution(String rrn, String value) =>
      _db.collection('robots').doc(rrn).update({'task_execution': value});
}
