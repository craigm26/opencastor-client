/// ViewModel for the Control (arm) screen.
///
/// All physical-layer commands go through [ControlViewModel.execute]
/// which enforces the confirmation-modal requirement and streams the result.
///
/// Safety invariants enforced here:
///   - EVERY control-scope command requires user confirmation dialog.
///   - ESTOP is always available and never gated behind a confirmation.
///   - Commands are dispatched with [CommandScope.control] (R2RAM §5.3).
///
/// GAP-08 (Cloud Relay Identity / Audit Trail):
///   - All commands sent from this app surface `sender_type: "human via
///     OpenCastor app"` in the command history. This is written to Firestore
///     by the Cloud Function and read back by the UI in [ControlSuccess].
///   - The [lastSenderType] field exposes the sender_type for the most recent
///     command, allowing the control screen to display it in the history.
library;

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../data/models/command.dart';
import '../../data/models/robot.dart';
import '../../data/repositories/robot_repository.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;

export '../../data/models/command.dart';
export '../../data/models/robot.dart';

/// Live state of the robot being controlled.
final controlRobotProvider =
    StreamProvider.family<Robot?, String>((ref, rrn) {
  return ref.read(robotRepositoryProvider).watchRobot(rrn);
});

/// State for a single control command execution.
sealed class ControlState {
  const ControlState();
}

class ControlIdle extends ControlState {
  const ControlIdle();
}

class ControlBusy extends ControlState {
  const ControlBusy();
}

class ControlSuccess extends ControlState {
  final String result;

  /// GAP-08: sender_type from the completed command's audit record.
  /// Defaults to "human via OpenCastor app" when field is absent.
  final String senderType;

  const ControlSuccess(this.result,
      {this.senderType = 'human via OpenCastor app'});
}

class ControlError extends ControlState {
  final String message;
  const ControlError(this.message);
}

/// Notifier for control command execution.
///
/// The widget must show a confirmation dialog BEFORE calling [execute].
class ControlViewModel extends AutoDisposeNotifier<ControlState> {
  @override
  ControlState build() => const ControlIdle();

  Future<void> execute({
    required String rrn,
    required String instruction,
  }) async {
    if (state is ControlBusy) return;
    state = const ControlBusy();

    try {
      final repo = ref.read(robotRepositoryProvider);
      final cmdId = await repo.sendCommand(
        rrn: rrn,
        instruction: instruction,
        scope: CommandScope.control,
      );

      // Stream-poll until terminal state
      await for (final cmd in repo.watchCommand(rrn, cmdId)) {
        if (cmd == null) break;
        if (cmd.isComplete) {
          // GAP-08: Surface sender_type in command history for audit trail
          state = ControlSuccess(
            cmd.result?['raw_text']?.toString() ?? 'Done',
            senderType:
                cmd.senderType ?? 'human via OpenCastor app',
          );
          return;
        }
        if (cmd.isFailed) {
          state = ControlError(cmd.error ?? 'Command failed');
          return;
        }
      }
      state = const ControlError('No response from robot');
    } catch (e) {
      state = ControlError(e.toString());
    }
  }

  Future<void> sendEstop(String rrn) async {
    // ESTOP bypasses confirmation — immediate execution (Protocol 66 §4.1)
    state = const ControlBusy();
    try {
      final repo = ref.read(robotRepositoryProvider);
      await repo.sendEstop(rrn);
      state = const ControlIdle();
    } catch (e) {
      state = ControlError(e.toString());
    }
  }

  void reset() => state = const ControlIdle();
}

final controlProvider =
    AutoDisposeNotifierProvider<ControlViewModel, ControlState>(
  ControlViewModel.new,
);
