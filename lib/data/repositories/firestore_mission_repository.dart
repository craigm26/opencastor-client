/// Firestore + Cloud Functions implementation of [MissionRepository].
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/app_logger.dart';
import 'mission_repository.dart';

class FirestoreMissionRepository implements MissionRepository {
  final FirebaseFirestore _db;
  final FirebaseFunctions _fn;

  FirestoreMissionRepository({FirebaseFirestore? db, FirebaseFunctions? fn})
      : _db = db ?? FirebaseFirestore.instance,
        _fn = fn ?? FirebaseFunctions.instance;

  @override
  Stream<List<MissionMessage>> watchMissions(String missionId,
      {int limit = 50}) {
    log.d('FirestoreMissionRepository.watchMissions: missionId="$missionId"');
    return _db
        .collection('missions')
        .doc(missionId)
        .collection('messages')
        .orderBy('timestamp')
        .limitToLast(limit)
        .snapshots()
        .map((snap) =>
            snap.docs.map(MissionMessage.fromDocument).toList())
        .handleError((e, st) {
      log.e('watchMissions ERROR — missionId="$missionId"',
          error: e, stackTrace: st as StackTrace?);
    });
  }

  @override
  Future<void> sendMission(String missionId, MissionMessage mission) async {
    log.d('FirestoreMissionRepository.sendMission: missionId="$missionId"');
    final fn = _fn.httpsCallable('sendMissionMessage');
    await fn.call({'missionId': missionId, 'content': mission.content});
  }
}
