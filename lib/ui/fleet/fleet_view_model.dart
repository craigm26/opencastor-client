/// ViewModel for the Fleet screen.
///
/// Exposes the live fleet stream as a [StreamProvider] that automatically
/// rebuilds when auth state changes (sign-in / sign-out).
///
/// Architecture: this file owns all providers for the fleet feature.
/// The [FleetScreen] widget is view-only — no business logic.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/robot.dart';
import '../../data/repositories/robot_repository.dart';
import '../../data/services/firestore_robot_service.dart';

export '../../data/models/robot.dart';
export '../../data/repositories/robot_repository.dart';

/// Provides the concrete [RobotRepository] implementation.
/// Override in tests with [ProviderScope] overrides.
final robotRepositoryProvider = Provider<RobotRepository>(
  (_) => FirestoreRobotService(),
);

/// Live fleet stream, scoped to the currently authenticated user.
///
/// Returns [Stream.empty()] when the user is not signed in (avoids
/// Firestore permission-denied errors and redundant queries).
/// Rebuilds automatically when auth state changes.
final fleetProvider = StreamProvider<List<Robot>>((ref) {
  final auth = ref.watch(authStateProvider);
  final user = auth.asData?.value;
  if (user == null) return const Stream.empty();
  return ref.read(robotRepositoryProvider).watchFleet(user.uid);
});

/// Auth state stream — single source of truth for sign-in status.
final authStateProvider = StreamProvider<User?>(
  (_) => FirebaseAuth.instance.authStateChanges(),
);
