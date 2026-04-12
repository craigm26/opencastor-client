/// ViewModel for the Robot Detail screen.
///
/// Provides live streams for a single robot's state and command history.
/// Business logic (send chat, send estop) is here — the screen only calls
/// methods, it never talks to a repository directly.
///
/// LAN mode:
///   When [lanModeProvider(rrn)] is true and a token + local_ip are available,
///   [SendChatNotifier.send] routes directly to the robot's local REST API
///   (http://[local_ip]:8000/api/command) instead of Firebase Cloud Functions.
///   LAN responses are appended to [lanLocalCommandsProvider] and merged into
///   [mergedCommandsProvider] so they appear inline in the chat history.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/models/command.dart';
import '../../data/models/robot.dart';
import '../../data/repositories/lan_mode_provider.dart';
import '../../data/repositories/robot_repository.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;

export '../../data/models/command.dart';
export '../../data/models/robot.dart';
export '../../data/repositories/lan_mode_provider.dart';
export '../../data/repositories/robot_repository.dart';

/// Live state of a single robot identified by [rrn].
final robotDetailProvider =
    StreamProvider.family<Robot?, String>((ref, rrn) {
  return ref.read(robotRepositoryProvider).watchRobot(rrn);
});

/// Live command history for [rrn] from Firestore (most recent first).
final commandsProvider =
    StreamProvider.family<List<RobotCommand>, String>((ref, rrn) {
  return ref.read(robotRepositoryProvider).watchCommands(rrn, limit: 30);
});

/// Merged command history: LAN commands (in-memory) + Firestore commands.
///
/// LAN commands appear first so the user sees responses immediately.
/// Firestore commands fill in the persistent history behind them.
final mergedCommandsProvider =
    StreamProvider.family<List<RobotCommand>, String>((ref, rrn) async* {
  final lanCmds = ref.watch(lanLocalCommandsProvider(rrn));
  await for (final firestoreCmds in ref.watch(commandsProvider(rrn).stream)) {
    // Deduplicate: skip Firestore entries whose ID matches a LAN synthetic ID
    final lanIds = lanCmds.map((c) => c.id).toSet();
    final deduped = firestoreCmds.where((c) => !lanIds.contains(c.id)).toList();
    yield [...lanCmds, ...deduped];
  }
});

// ── Send chat command ─────────────────────────────────────────────────────────

/// Notifier for the "send chat" action — tracks loading state per robot.
///
/// When LAN mode is active, sends via [LanRobotService] and adds the response
/// to [lanLocalCommandsProvider].  Falls back to Firebase Cloud Functions when
/// LAN is disabled or the robot is unreachable via LAN.
class SendChatNotifier extends AutoDisposeAsyncNotifier<String?> {
  @override
  Future<String?> build() async => null;

  Future<String?> send({
    required String rrn,
    required String instruction,
    List<Map<String, dynamic>>? mediaChunks,
  }) async {
    state = const AsyncLoading();
    String? cmdId;
    state = await AsyncValue.guard(() async {
      // ── LAN path ────────────────────────────────────────────────────────────
      final robot = ref.read(robotDetailProvider(rrn)).valueOrNull;
      final localIp = robot?.telemetry['local_ip'] as String?;
      final lan = await buildLanService(ref, rrn, localIp: localIp);

      if (lan != null) {
        final result = await lan.sendCommand(
          instruction: instruction,
          mediaChunks: mediaChunks,
        );
        cmdId = result.cmdId;

        // Synthesise a RobotCommand so it appears in the chat list
        final syntheticCmd = RobotCommand(
          id: result.cmdId,
          instruction: instruction,
          scope: CommandScope.chat,
          issuedByUid: 'local',
          issuedAt: DateTime.now(),
          status: CommandStatus.complete,
          completedAt: DateTime.now(),
          result: {
            'raw_text': result.rawText,
            if (result.action != null) 'action': result.action,
          },
          senderType: 'human via OpenCastor app (LAN)',
        );
        ref.read(lanLocalCommandsProvider(rrn).notifier).update(
              (list) => [syntheticCmd, ...list],
            );
        return cmdId;
      }

      // ── Firebase cloud path ─────────────────────────────────────────────────
      cmdId = await ref.read(robotRepositoryProvider).sendCommand(
            rrn: rrn,
            instruction: instruction,
            scope: CommandScope.chat,
            mediaChunks: mediaChunks,
          );
      return cmdId;
    });
    return cmdId;
  }
}

final sendChatProvider =
    AsyncNotifierProvider.autoDispose<SendChatNotifier, String?>(
  SendChatNotifier.new,
);

/// Fetches the latest opencastor version from PyPI (cached for the session).
/// Used by the version badge in [RobotDetailScreen].
final latestVersionProvider = FutureProvider<String?>((ref) async {
  try {
    final resp = await http
        .get(
          Uri.parse('https://pypi.org/pypi/opencastor/json'),
          headers: {'Accept': 'application/json'},
        )
        .timeout(const Duration(seconds: 6));
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return (data['info'] as Map<String, dynamic>)['version'] as String?;
    }
  } catch (_) {}
  return null;
});
