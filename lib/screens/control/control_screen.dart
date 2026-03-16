import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/command.dart';
import '../../models/robot.dart';
import '../../services/robot_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/health_indicator.dart';

final _svcProvider = Provider((_) => RobotService());
final _robotProvider = StreamProvider.family<Robot?, String>(
  (ref, rrn) => ref.read(_svcProvider).watchRobot(rrn),
);

class ControlScreen extends ConsumerStatefulWidget {
  final String rrn;
  const ControlScreen({super.key, required this.rrn});

  @override
  ConsumerState<ControlScreen> createState() => _State();
}

class _State extends ConsumerState<ControlScreen> {
  final _instrCtrl = TextEditingController();
  bool _busy = false;
  String? _lastResult;
  String? _lastError;

  @override
  void dispose() {
    _instrCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendControl(Robot robot, String instruction) async {
    if (_busy) return;

    // Always require confirmation for control-scope commands
    final confirmed = await showConfirmationDialog(
      context,
      title: 'Send control command',
      body: '"$instruction"\n\nThis instruction will be executed by ${robot.name}\'s arm.',
      confirmLabel: 'Execute',
      isDangerous: true,
    );
    if (!confirmed || !mounted) return;

    setState(() {
      _busy = true;
      _lastResult = null;
      _lastError = null;
    });

    try {
      final svc = ref.read(_svcProvider);
      final cmdId = await svc.sendCommand(
        rrn: robot.rrn,
        instruction: instruction,
        scope: CommandScope.control,
      );

      // Wait for result (stream-based polling)
      await for (final cmd in svc.watchCommand(robot.rrn, cmdId)) {
        if (cmd == null) break;
        if (cmd.isComplete) {
          setState(() {
            _lastResult = cmd.result?['raw_text']?.toString() ?? 'Done';
          });
          break;
        }
        if (cmd.isFailed) {
          setState(() {
            _lastError = cmd.error ?? 'Command failed';
          });
          break;
        }
      }
    } catch (e) {
      setState(() => _lastError = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _sendEstop(Robot robot) async {
    final confirmed = await showEstopDialog(context, robot.name);
    if (!confirmed || !mounted) return;
    try {
      await ref.read(_svcProvider).sendEstop(robot.rrn);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('ESTOP sent'),
            backgroundColor: AppTheme.estop,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('ESTOP failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final robotAsync = ref.watch(_robotProvider(widget.rrn));
    return robotAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return const Scaffold(
              body: Center(child: Text('Robot not found')));
        }
        return _buildControl(context, robot);
      },
    );
  }

  Widget _buildControl(BuildContext context, Robot robot) {
    final isOnline = robot.isOnline;

    return Scaffold(
      appBar: AppBar(
        title: Text('Control — ${robot.name}'),
        actions: [
          HealthIndicator(isOnline: isOnline, size: 8),
          const SizedBox(width: 8),
          // Persistent ESTOP button in AppBar
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: isOnline ? () => _sendEstop(robot) : null,
              icon: const Icon(Icons.stop_circle_outlined, size: 16),
              label: const Text('ESTOP'),
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.estop,
                minimumSize: const Size(0, 36),
              ),
            ),
          ),
        ],
      ),
      body: !isOnline
          ? _OfflineBanner(robotName: robot.name)
          : Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Warning banner
                  _SafetyBanner(),
                  const SizedBox(height: 16),

                  // Quick-action buttons
                  Text('Quick actions',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  _QuickActions(
                    busy: _busy,
                    onAction: (instr) => _sendControl(robot, instr),
                  ),
                  const SizedBox(height: 20),

                  // Free-form instruction
                  Text('Custom instruction',
                      style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _instrCtrl,
                          enabled: !_busy,
                          decoration: const InputDecoration(
                            hintText: 'e.g. "Move elbow to 90°"',
                            border: OutlineInputBorder(),
                          ),
                          textInputAction: TextInputAction.send,
                          onSubmitted: (v) =>
                              _sendControl(robot, v),
                        ),
                      ),
                      const SizedBox(width: 8),
                      _busy
                          ? const SizedBox(
                              width: 48,
                              height: 48,
                              child: Padding(
                                padding: EdgeInsets.all(12),
                                child: CircularProgressIndicator(
                                    strokeWidth: 2),
                              ),
                            )
                          : IconButton.filled(
                              onPressed: () =>
                                  _sendControl(robot, _instrCtrl.text),
                              icon: const Icon(Icons.send_outlined),
                            ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Result / error
                  if (_lastResult != null)
                    _ResultCard(text: _lastResult!, isError: false),
                  if (_lastError != null)
                    _ResultCard(text: _lastError!, isError: true),
                ],
              ),
            ),
    );
  }
}

class _SafetyBanner extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: AppTheme.warning.withOpacity(0.12),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppTheme.warning.withOpacity(0.4)),
      ),
      child: Row(
        children: const [
          Icon(Icons.warning_amber_rounded, color: AppTheme.warning, size: 16),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'Control-scope commands physically move the robot arm. '
              'Ensure the workspace is clear before each action.',
              style: TextStyle(fontSize: 12, color: AppTheme.warning),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActions extends StatelessWidget {
  final bool busy;
  final void Function(String) onAction;

  const _QuickActions({required this.busy, required this.onAction});

  static const _actions = [
    ('Home position', Icons.home_outlined, 'Move all joints to home position'),
    ('Open gripper', Icons.pan_tool_outlined, 'Open the gripper fully'),
    ('Close gripper', Icons.back_hand_outlined, 'Close the gripper'),
    ('Extend reach', Icons.open_in_full_outlined, 'Extend arm forward at mid-height'),
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: _actions
          .map(
            (a) => ActionChip(
              avatar: Icon(a.$2, size: 14),
              label: Text(a.$1, style: const TextStyle(fontSize: 12)),
              onPressed: busy ? null : () => onAction(a.$3),
            ),
          )
          .toList(),
    );
  }
}

class _ResultCard extends StatelessWidget {
  final String text;
  final bool isError;
  const _ResultCard({required this.text, required this.isError});

  @override
  Widget build(BuildContext context) {
    final color = isError ? AppTheme.danger : AppTheme.online;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle_outline,
            color: color,
            size: 16,
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(text, style: TextStyle(fontSize: 12, color: color))),
        ],
      ),
    );
  }
}

class _OfflineBanner extends StatelessWidget {
  final String robotName;
  const _OfflineBanner({required this.robotName});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 64, color: AppTheme.offline),
            const SizedBox(height: 16),
            Text('$robotName is offline',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('Start  castor bridge  on the robot to enable remote control.',
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
