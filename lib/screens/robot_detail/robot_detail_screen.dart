import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../models/command.dart';
import '../../models/robot.dart';
import '../../services/robot_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/capability_badge.dart';
import '../../widgets/confirmation_dialog.dart';
import '../../widgets/health_indicator.dart';

final _svcProvider = Provider((_) => RobotService());

final robotDetailProvider =
    StreamProvider.family<Robot?, String>((ref, rrn) {
  return ref.read(_svcProvider).watchRobot(rrn);
});

final commandsProvider =
    StreamProvider.family<List<RobotCommand>, String>((ref, rrn) {
  return ref.read(_svcProvider).watchCommands(rrn, limit: 30);
});

class RobotDetailScreen extends ConsumerStatefulWidget {
  final String rrn;
  const RobotDetailScreen({super.key, required this.rrn});

  @override
  ConsumerState<RobotDetailScreen> createState() => _State();
}

class _State extends ConsumerState<RobotDetailScreen> {
  final _ctrl = TextEditingController();
  bool _sending = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _sendChat(Robot robot) async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    setState(() => _sending = true);
    _ctrl.clear();
    try {
      await ref.read(_svcProvider).sendCommand(
            rrn: robot.rrn,
            instruction: text,
            scope: CommandScope.chat,
          );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final robotAsync = ref.watch(robotDetailProvider(widget.rrn));
    final commandsAsync = ref.watch(commandsProvider(widget.rrn));

    return robotAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return const Scaffold(body: Center(child: Text('Robot not found')));
        }
        return _build(context, robot, commandsAsync);
      },
    );
  }

  Widget _build(
    BuildContext context,
    Robot robot,
    AsyncValue<List<RobotCommand>> commandsAsync,
  ) {
    final cs = Theme.of(context).colorScheme;
    final svc = ref.read(_svcProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(robot.name),
        actions: [
          HealthIndicator(isOnline: robot.isOnline, size: 8),
          const SizedBox(width: 8),
          if (robot.hasCapability(RobotCapability.control))
            IconButton(
              icon: const Icon(Icons.precision_manufacturing_outlined),
              tooltip: 'Control arm',
              onPressed: () => context.push('/robot/${robot.rrn}/control'),
            ),
          if (robot.isOnline)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined, color: AppTheme.estop),
              tooltip: 'ESTOP',
              onPressed: () async {
                final ok = await showEstopDialog(context, robot.name);
                if (ok && context.mounted) await svc.sendEstop(robot.rrn);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // Telemetry panel
          _TelemetryPanel(robot: robot),
          const Divider(height: 1),

          // Command history
          Expanded(
            child: commandsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (cmds) => cmds.isEmpty
                  ? Center(
                      child: Text('No commands yet',
                          style: TextStyle(color: cs.onSurfaceVariant)),
                    )
                  : ListView.builder(
                      reverse: true,
                      padding: const EdgeInsets.all(12),
                      itemCount: cmds.length,
                      itemBuilder: (_, i) => _CommandTile(cmd: cmds[i]),
                    ),
            ),
          ),

          // Chat input (only for chat-capable robots)
          if (robot.hasCapability(RobotCapability.chat) && robot.isOnline)
            _ChatInput(
              ctrl: _ctrl,
              sending: _sending,
              onSend: () => _sendChat(robot),
            ),
        ],
      ),
    );
  }
}

class _TelemetryPanel extends StatelessWidget {
  final Robot robot;
  const _TelemetryPanel({required this.robot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = robot.telemetry;

    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Capabilities
          Expanded(
            child: CapabilityRow(capabilities: robot.capabilities, compact: true),
          ),
          // Key metrics
          if (t['cpu_temp'] != null)
            _Metric(Icons.thermostat_outlined, '${(t['cpu_temp'] as num).toStringAsFixed(0)}°C'),
          if (t['disk_pct'] != null)
            _Metric(Icons.storage_outlined, '${(t['disk_pct'] as num).toStringAsFixed(0)}%'),
          _Metric(Icons.tag_outlined, robot.version),
        ],
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  final IconData icon;
  final String value;
  const _Metric(this.icon, this.value);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(value, style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _CommandTile extends StatelessWidget {
  final RobotCommand cmd;
  const _CommandTile({required this.cmd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isMe = cmd.scope == CommandScope.chat;

    Color statusColor = cs.onSurfaceVariant;
    IconData statusIcon = Icons.schedule_outlined;
    if (cmd.isComplete) {
      statusColor = AppTheme.online;
      statusIcon = Icons.check_circle_outline;
    } else if (cmd.isFailed) {
      statusColor = AppTheme.danger;
      statusIcon = Icons.error_outline;
    } else if (cmd.isPending) {
      statusIcon = Icons.hourglass_empty;
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(statusIcon, size: 16, color: statusColor),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(cmd.instruction,
                    style: const TextStyle(fontSize: 13)),
                if (cmd.result != null && cmd.result!['raw_text'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      cmd.result!['raw_text'].toString(),
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                    ),
                  ),
                if (cmd.error != null)
                  Text(cmd.error!,
                      style: const TextStyle(
                          fontSize: 11, color: AppTheme.danger)),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _fmt(cmd.issuedAt),
            style: TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      DateFormat('HH:mm:ss').format(dt.toLocal());
}

class _ChatInput extends StatelessWidget {
  final TextEditingController ctrl;
  final bool sending;
  final VoidCallback onSend;

  const _ChatInput({
    required this.ctrl,
    required this.sending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: ctrl,
                decoration: const InputDecoration(
                  hintText: 'Send instruction…',
                  isDense: true,
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            sending
                ? const SizedBox(
                    width: 36,
                    height: 36,
                    child: Padding(
                      padding: EdgeInsets.all(8),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  )
                : IconButton.filled(
                    onPressed: onSend,
                    icon: const Icon(Icons.send_outlined),
                    iconSize: 18,
                  ),
          ],
        ),
      ),
    );
  }
}
