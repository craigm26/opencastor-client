/// ViewModel for the Robot Detail screen.
///
/// Provides live streams for a single robot's state and command history.
/// Business logic (send chat, send estop) is here — the screen only calls
/// methods, it never talks to a repository directly.
library;

import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/models/command.dart';
import '../../data/models/robot.dart';
import '../../data/repositories/robot_repository.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;

export '../../data/models/command.dart';
export '../../data/models/robot.dart';
export '../../data/repositories/robot_repository.dart';

/// Live state of a single robot identified by [rrn].
final robotDetailProvider =
    StreamProvider.family<Robot?, String>((ref, rrn) {
  return ref.read(robotRepositoryProvider).watchRobot(rrn);
});

/// Live command history for [rrn] (most recent first).
final commandsProvider =
    StreamProvider.family<List<RobotCommand>, String>((ref, rrn) {
  return ref.read(robotRepositoryProvider).watchCommands(rrn, limit: 30);
});

/// Notifier for the "send chat" action — tracks loading state per robot.
/// Returns the newly-created command ID so the caller can track it.
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
