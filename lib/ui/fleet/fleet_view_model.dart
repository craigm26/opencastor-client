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
import '../../data/repositories/robot_repository_provider.dart';

export '../../data/repositories/robot_repository.dart';
// Re-export so existing UI files that `show robotRepositoryProvider` from here
// continue to resolve without changes.
export '../../data/repositories/robot_repository_provider.dart'
    show robotRepositoryProvider;

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Auth state stream — single source of truth for sign-in status.
final authStateProvider = StreamProvider<User?>((_) async* {
  // On iOS, Firebase checks persisted credentials asynchronously — the first
  // authStateChanges() event can arrive several seconds after cold start.
  // Without a guard the router would sit on /splash forever (looks like a
  // black-screen crash).
  //
  // Fix: race the first emission against a 10s deadline. If no event arrives
  // in time we yield null so the router falls through to /login.
  //
  // IMPORTANT: the timeout applies ONLY to the first emission. After that the
  // stream passes through with no timeout. The previous implementation used
  // .timeout() on the entire stream, which re-arms every 10 s of inactivity
  // (i.e. while the user is authenticated and auth state is stable). That
  // caused a hard redirect to /login after ~10 s on any screen — the
  // "auth loop on robot detail" bug.
  final stream = FirebaseAuth.instance.authStateChanges();
  bool firstEmitted = false;

  await for (final user in stream.timeout(
    const Duration(seconds: 10),
    onTimeout: (sink) {
      if (!firstEmitted) sink.add(null); // only emit null if still waiting
    },
  )) {
    firstEmitted = true;
    yield user;
    // After the first value, break out and re-subscribe WITHOUT a timeout
    break;
  }

  // Tail: pass remaining events through with no timeout
  yield* stream;
});

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
