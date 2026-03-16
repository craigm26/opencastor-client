/// ViewModel for the Robot Detail screen.
///
/// Provides live streams for a single robot's state and command history.
/// Business logic (send chat, send estop) is here — the screen only calls
/// methods, it never talks to a repository directly.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
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
class SendChatNotifier extends AutoDisposeAsyncNotifier<void> {
  @override
  Future<void> build() async {}

  Future<void> send({
    required String rrn,
    required String instruction,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(
      () => ref.read(robotRepositoryProvider).sendCommand(
            rrn: rrn,
            instruction: instruction,
            scope: CommandScope.chat,
          ),
    );
  }
}

final sendChatProvider =
    AsyncNotifierProvider.autoDispose<SendChatNotifier, void>(
  SendChatNotifier.new,
);
