import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/app_logger.dart';
import '../models/command.dart';
import '../models/robot.dart';
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
  }) async {
    final callable = _fn.httpsCallable('sendCommand');
    final result = await callable.call({
      'rrn': rrn,
      'instruction': instruction,
      'scope': scope.name,
      if (reason != null) 'reason': reason,
      if (mediaChunks != null) 'media_chunks': mediaChunks,
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
        .map((snap) => snap.docs.map(RobotCommand.fromDoc).toList());
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
}
