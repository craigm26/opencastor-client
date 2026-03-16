/// ViewModel for the Fleet screen.
///
/// Architecture (MVVM — https://docs.flutter.dev/app-architecture/guide):
///   - [FleetScreen] is the View — no business logic, calls commands only
///   - This file is the ViewModel — owns providers, exposes commands to the View
///   - [RobotRepository] is the data source — View never touches it directly
///
/// Commands exposed to the view:
///   - [fleetProvider]        — live fleet data stream
///   - [EstopCommand]         — send ESTOP to a robot (never rate-limited)
///
/// The View must NEVER call [robotRepositoryProvider] directly.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/app_logger.dart';
import '../../data/models/robot.dart';
import '../../data/repositories/robot_repository.dart';
import '../../data/services/firestore_robot_service.dart';

export '../../data/models/robot.dart';
export '../../data/repositories/robot_repository.dart';

// ---------------------------------------------------------------------------
// Dependency injection
// ---------------------------------------------------------------------------

/// Provides the concrete [RobotRepository] implementation.
/// Override in tests with ProviderScope overrides:
///   overrides: [robotRepositoryProvider.overrideWithValue(MockRobotRepository())]
final robotRepositoryProvider = Provider<RobotRepository>(
  (_) => FirestoreRobotService(),
);

/// Auth state stream — single source of truth for sign-in status.
final authStateProvider = StreamProvider<User?>(
  (_) => FirebaseAuth.instance.authStateChanges(),
);

// ---------------------------------------------------------------------------
// Fleet data stream
// ---------------------------------------------------------------------------

/// Live fleet stream, scoped to the currently authenticated user.
///
/// Returns [Stream.empty()] when the user is not signed in — avoids
/// Firestore permission-denied errors and unnecessary queries.
/// Rebuilds automatically when auth state changes.
final fleetProvider = StreamProvider<List<Robot>>((ref) {
  final auth = ref.watch(authStateProvider);

  if (auth.isLoading) {
    log.d('fleetProvider: auth still loading — waiting');
    return const Stream.empty();
  }

  final user = auth.asData?.value;
  if (user == null) {
    log.i('fleetProvider: user is null (signed out) — empty stream');
    return const Stream.empty();
  }

  log.i('fleetProvider: querying Firestore with uid=${user.uid} email=${user.email}');

  return ref.read(robotRepositoryProvider).watchFleet(user.uid).map((robots) {
    log.i('fleetProvider: Firestore returned ${robots.length} robot(s): ${robots.map((r) => r.rrn).join(', ')}');
    return robots;
  });
});

// ---------------------------------------------------------------------------
// Commands (guide: https://docs.flutter.dev/app-architecture/guide#commands)
//
// Commands are ViewModel methods exposed to the View for user interactions.
// Views call commands; commands call the repository.
// Views never interact with repositories directly.
// ---------------------------------------------------------------------------

/// State for the ESTOP command.
sealed class EstopState {
  const EstopState();
}
class EstopIdle extends EstopState {
  const EstopIdle();
}
class EstopSending extends EstopState {
  final String rrn;
  const EstopSending(this.rrn);
}
class EstopSent extends EstopState {
  final String rrn;
  const EstopSent(this.rrn);
}
class EstopError extends EstopState {
  final String rrn;
  final String message;
  const EstopError(this.rrn, this.message);
}

/// ESTOP command — bypasses all rate limiting (Protocol 66 §4.1).
///
/// Views call: `ref.read(estopCommandProvider.notifier).send(rrn)`
/// Views observe: `ref.watch(estopCommandProvider)` for loading/error state.
class EstopCommand extends AutoDisposeNotifier<EstopState> {
  @override
  EstopState build() => const EstopIdle();

  /// Send ESTOP to [rrn]. Never requires confirmation (immediate execution).
  Future<void> send(String rrn) async {
    if (state is EstopSending) return; // debounce
    state = EstopSending(rrn);
    try {
      await ref.read(robotRepositoryProvider).sendEstop(rrn);
      state = EstopSent(rrn);
    } catch (e) {
      state = EstopError(rrn, e.toString());
    }
  }

  void reset() => state = const EstopIdle();
}

final estopCommandProvider =
    AutoDisposeNotifierProvider<EstopCommand, EstopState>(
  EstopCommand.new,
);
