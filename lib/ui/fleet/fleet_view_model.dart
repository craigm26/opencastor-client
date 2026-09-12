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
import '../../data/repositories/lan_mode_provider.dart';
import '../../data/repositories/robot_repository_provider.dart';
import '../shared/estop_feedback.dart';

export '../../data/repositories/robot_repository.dart';
export '../shared/estop_feedback.dart'
    show EstopAck, estopAckFromQos, estopAckMessage, buildEstopSnackBar;
export '../../data/repositories/lan_mode_provider.dart' show lanModeProvider;
// Re-export so existing UI files that `show robotRepositoryProvider` from here
// continue to resolve without changes.
export '../../data/repositories/robot_repository_provider.dart'
    show robotRepositoryProvider;

// ---------------------------------------------------------------------------
// Auth
// ---------------------------------------------------------------------------

/// Auth state stream — single source of truth for sign-in status.
/// Auth state stream — single source of truth for sign-in status.
///
/// Uses [FirebaseAuth.authStateChanges] directly with no timeout wrapper.
///
/// History of bugs avoided here:
/// - v1: .timeout(8s) on the full stream → re-armed every 8 s of inactivity,
///   emitting null while authenticated → kicked user to /login on robot detail.
/// - v2: break-then-yield* approach → created a second subscription that
///   immediately emitted null before Firebase resolved credentials → same loop.
///
/// The router redirect guards against AsyncLoading with a /splash redirect,
/// which is correct. Firebase web SDK emits within milliseconds on subsequent
/// visits (credentials cached in IndexedDB). No timeout needed.
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
/// The stop was accepted into the cloud queue. OC-M-01: this says nothing
/// about motion — the bridge may not have read the document yet.
class EstopQueued extends EstopState {
  final String rrn;
  final String? cmdId;
  const EstopQueued(this.rrn, {this.cmdId});
}

/// A dispatch result came back: the robot's own LAN API answered 2xx, or the
/// bridge stamped `ack_qos: acknowledged` onto the command document.
class EstopConfirmed extends EstopState {
  final String rrn;

  /// 'lan' when the robot answered directly, 'cloud' when the bridge did.
  final String source;
  const EstopConfirmed(this.rrn, {required this.source});
}

/// Dispatched, but no acknowledgement arrived before the deadline, or the
/// bridge reported the dispatch failed.
class EstopNotConfirmed extends EstopState {
  final String rrn;
  final String reason;
  const EstopNotConfirmed(this.rrn, this.reason);
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
  bool _disposed = false;

  @override
  EstopState build() {
    ref.onDispose(() => _disposed = true);
    return const EstopIdle();
  }

  void _set(EstopState next) {
    if (_disposed) return;
    state = next;
  }

  /// Send ESTOP to [rrn]. Never requires confirmation (immediate execution).
  ///
  /// When LAN mode is enabled for [rrn], attempts to send ESTOP directly to
  /// the robot's local API for minimum latency (~30 ms vs ~500 ms cloud).
  /// Falls back to Firebase Cloud Functions if LAN send fails.
  ///
  /// OC-M-01 — the two branches do NOT know the same thing, and the state they
  /// publish now says so:
  ///   * LAN: `POST /api/stop` answered 2xx from the robot itself. That is a
  ///     dispatch result, so the state is [EstopConfirmed].
  ///   * Cloud: `sendEstop` only wrote a command document. That is a queue
  ///     acceptance, so the state is [EstopQueued] until the bridge stamps
  ///     `ack_qos` onto the document from its own dispatch result.
  Future<void> send(String rrn) async {
    if (state is EstopSending) return; // debounce
    _set(EstopSending(rrn));
    try {
      // ── Try LAN ESTOP first if enabled ─────────────────────────────────────
      final fleet = ref.read(fleetProvider).valueOrNull;
      final robot = fleet?.where((r) => r.rrn == rrn).firstOrNull;
      final localIp = robot?.telemetry['local_ip'] as String?;
      final lan = await buildLanService(ref, rrn, localIp: localIp);

      if (lan != null) {
        try {
          await lan.sendEstop();
          _set(EstopConfirmed(rrn, source: 'lan'));
          return;
        } catch (_) {
          // LAN ESTOP failed — fall through to cloud relay
          log.w('LAN ESTOP failed for $rrn — falling back to Firebase');
        }
      }

      // ── Firebase cloud relay ────────────────────────────────────────────────
      final cmdId = await ref.read(robotRepositoryProvider).sendEstop(rrn);
      _set(EstopQueued(rrn, cmdId: cmdId));
      await _awaitCloudAck(rrn, cmdId);
    } catch (e) {
      _set(EstopError(rrn, e.toString()));
    }
  }

  /// Promote [EstopQueued] to confirmed or not-confirmed once the bridge's
  /// dispatch result lands on the command document. A deadline that passes in
  /// silence is [EstopNotConfirmed]: no acknowledgement means no stop.
  Future<void> _awaitCloudAck(String rrn, String cmdId) async {
    EstopAck ack;
    try {
      ack = await ref
          .read(robotRepositoryProvider)
          .watchCommand(rrn, cmdId)
          .map((cmd) => estopAckFromQos(cmd?.ackQos))
          .firstWhere(
            (a) => a != EstopAck.queued,
            orElse: () => EstopAck.notConfirmed,
          )
          .timeout(kEstopAckDeadline);
    } catch (_) {
      ack = EstopAck.notConfirmed;
    }
    if (ack == EstopAck.confirmed) {
      _set(EstopConfirmed(rrn, source: 'cloud'));
    } else {
      _set(EstopNotConfirmed(rrn, 'no stop acknowledgement from the robot'));
    }
  }

  void reset() => _set(const EstopIdle());
}

final estopCommandProvider =
    AutoDisposeNotifierProvider<EstopCommand, EstopState>(
  EstopCommand.new,
);
