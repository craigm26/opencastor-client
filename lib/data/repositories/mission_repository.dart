/// Abstract contract for Mission message operations.
///
/// Concrete implementations:
///   - [FirestoreMissionRepository] — production, reads from Firebase
///   - MockMissionRepository        — testing / offline development
///
/// Depend on [MissionRepository], never on the concrete class.
/// The DI binding is in [missionRepositoryProvider].
library;

import '../models/mission.dart';

export '../models/mission.dart';

abstract class MissionRepository {
  /// Live stream of messages for the given [missionId] (chronological order).
  Stream<List<MissionMessage>> watchMissions(String missionId,
      {int limit = 50});

  /// Send a mission message to [missionId].
  Future<void> sendMission(String missionId, MissionMessage mission);
}
