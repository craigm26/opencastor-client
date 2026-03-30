/// Global Riverpod provider for [RobotRepository].
///
/// Returns the [FirestoreRobotService] concrete implementation.
/// Override in tests:
///   overrides: [robotRepositoryProvider.overrideWithValue(MockRobotRepository())]
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/robot_repository.dart';
import '../services/firestore_robot_service.dart';

export '../repositories/robot_repository.dart';

final robotRepositoryProvider = Provider<RobotRepository>(
  (_) => FirestoreRobotService(),
);
