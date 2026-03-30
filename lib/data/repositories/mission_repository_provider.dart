/// Global Riverpod provider for [MissionRepository].
///
/// Returns the [FirestoreMissionRepository] concrete implementation.
/// Override in tests:
///   overrides: [missionRepositoryProvider.overrideWithValue(MockMissionRepository())]
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firestore_mission_repository.dart';
import 'mission_repository.dart';

export 'mission_repository.dart';

final missionRepositoryProvider = Provider<MissionRepository>(
  (_) => FirestoreMissionRepository(),
);
