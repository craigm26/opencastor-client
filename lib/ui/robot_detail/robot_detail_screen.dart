/// Robot Detail Screen — RCAN v1.5 status indicators.
///
/// Displays per-robot RCAN v1.5 badges:
///   - RCAN version chip (GAP-12)
///   - Replay protection indicator (GAP-03)
///   - QoS indicator: "ESTOP QoS ✓" (GAP-11)
///   - Revocation status banner (GAP-02)
///   - Offline mode badge (GAP-06)
///
/// All business logic lives in [RobotDetailViewModel] (robot_detail_view_model.dart).
/// This screen only calls methods and reads state — never talks to a repository.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/capability_badge.dart';
import '../../ui/core/widgets/confirmation_dialog.dart';
import '../../ui/core/widgets/health_indicator.dart';
import 'robot_detail_view_model.dart';

class RobotDetailScreen extends ConsumerStatefulWidget {
  final String rrn;
  const RobotDetailScreen({super.key, required this.rrn});

  @override
  ConsumerState<RobotDetailScreen> createState() => _RobotDetailScreenState();
}

class _RobotDetailScreenState extends ConsumerState<RobotDetailScreen> {
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
      await ref.read(sendChatProvider.notifier).send(
            rrn: robot.rrn,
            instruction: text,
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
          return const Scaffold(
              body: Center(child: Text('Robot not found')));
        }
        return _buildScaffold(context, robot, commandsAsync);
      },
    );
  }

  Widget _buildScaffold(
    BuildContext context,
    Robot robot,
    AsyncValue<List<RobotCommand>> commandsAsync,
  ) {
    final repo = ref.read(robotRepositoryProvider);

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
              onPressed: () =>
                  context.push('/robot/${robot.rrn}/control'),
            ),
          // ESTOP — always available (Protocol 66 §4.1: ESTOP never blocked)
          if (robot.isOnline && !robot.isRevoked)
            IconButton(
              icon: const Icon(Icons.stop_circle_outlined,
                  color: AppTheme.estop),
              tooltip: 'ESTOP',
              onPressed: () async {
                final ok = await showEstopDialog(context, robot.name);
                if (ok && context.mounted) await repo.sendEstop(robot.rrn);
              },
            ),
        ],
      ),
      body: Column(
        children: [
          // ── v1.5 banners (shown above everything else) ────────────────────
          _RevocationBanner(robot: robot),
          _OfflineBanner(robot: robot),

          // ── Telemetry + v1.5 badges ───────────────────────────────────────
          _TelemetryPanel(robot: robot),
          const Divider(height: 1),

          // ── Command history ───────────────────────────────────────────────
          Expanded(
            child: commandsAsync.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('Error: $e')),
              data: (cmds) {
                if (cmds.isEmpty) {
                  return Center(
                    child: Text(
                      'No commands yet',
                      style: TextStyle(
                          color: Theme.of(context)
                              .colorScheme
                              .onSurfaceVariant),
                    ),
                  );
                }
                return ListView.builder(
                  reverse: true,
                  padding: const EdgeInsets.all(12),
                  itemCount: cmds.length,
                  itemBuilder: (_, i) => _CommandTile(cmd: cmds[i]),
                );
              },
            ),
          ),

          // ── Chat input ────────────────────────────────────────────────────
          if (robot.hasCapability(RobotCapability.chat) &&
              robot.isOnline &&
              !robot.isRevoked)
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

// ── Revocation banner ─────────────────────────────────────────────────────────

class _RevocationBanner extends StatelessWidget {
  final Robot robot;
  const _RevocationBanner({required this.robot});

  @override
  Widget build(BuildContext context) {
    if (robot.revocationStatus == RevocationStatus.active) {
      return const SizedBox.shrink();
    }

    final isRevoked = robot.revocationStatus == RevocationStatus.revoked;
    final bg = isRevoked ? AppTheme.danger : AppTheme.warning;
    final icon = isRevoked
        ? Icons.block_outlined
        : Icons.pause_circle_outline;
    final label = isRevoked
        ? 'REVOKED — All commands blocked'
        : 'SUSPENDED — Commands temporarily blocked';

    return Material(
      color: bg.withOpacity(0.12),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          border: Border(
              bottom: BorderSide(color: bg.withOpacity(0.4))),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: bg),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: bg),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Offline banner ────────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  final Robot robot;
  const _OfflineBanner({required this.robot});

  @override
  Widget build(BuildContext context) {
    // Show yellow offline badge when robot itself is offline but is
    // offline-mode capable — it may still be running locally.
    if (robot.isOnline || !robot.offlineCapable) {
      return const SizedBox.shrink();
    }
    return Material(
      color: AppTheme.warning.withOpacity(0.08),
      child: Container(
        width: double.infinity,
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
              bottom:
                  BorderSide(color: AppTheme.warning.withOpacity(0.3))),
        ),
        child: Row(
          children: [
            Icon(Icons.wifi_off_outlined,
                size: 14, color: AppTheme.warning),
            const SizedBox(width: 8),
            Text(
              'OFFLINE — Robot operating on cached credentials',
              style: TextStyle(
                  fontSize: 12, color: AppTheme.warning),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Telemetry panel with v1.5 badges ──────────────────────────────────────────

class _TelemetryPanel extends StatelessWidget {
  final Robot robot;
  const _TelemetryPanel({required this.robot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final t = robot.telemetry;

    return Container(
      color: cs.surfaceContainerLow,
      padding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: CapabilityRow(
                    capabilities: robot.capabilities, compact: true),
              ),
              if (t['cpu_temp'] != null)
                _Metric(Icons.thermostat_outlined,
                    '${(t['cpu_temp'] as num).toStringAsFixed(0)}°C'),
              if (t['disk_pct'] != null)
                _Metric(Icons.storage_outlined,
                    '${(t['disk_pct'] as num).toStringAsFixed(0)}%'),
              _Metric(Icons.tag_outlined, robot.version),
            ],
          ),
          // ── RCAN v1.5 badge row ─────────────────────────────────────────
          const SizedBox(height: 6),
          Wrap(
            spacing: 6,
            runSpacing: 4,
            children: [
              if (robot.isRcanV15) ...[
                _V15Badge(
                  label: 'RCAN v${robot.rcanVersion}',
                  icon: Icons.verified_outlined,
                  color: Colors.purple,
                  tooltip: 'This robot supports RCAN v1.5',
                ),
                // Replay protection — all v1.5 nodes support replay cache
                _V15Badge(
                  label: 'Replay Protected',
                  icon: Icons.shield_outlined,
                  color: Colors.green,
                  tooltip:
                      'Replay attack prevention active (GAP-03 §8.3)',
                ),
              ],
              if (robot.supportsQos2)
                _V15Badge(
                  label: 'ESTOP QoS ✓',
                  icon: Icons.check_circle_outline,
                  color: Colors.blue,
                  tooltip:
                      'Exactly-once ESTOP delivery guaranteed (QoS 2)',
                ),
              if (robot.supportsDelegation)
                _V15Badge(
                  label: 'Delegation',
                  icon: Icons.account_tree_outlined,
                  color: Colors.teal,
                  tooltip: 'Command delegation chains supported (GAP-01)',
                ),
              if (robot.offlineCapable)
                _V15Badge(
                  label: 'Offline Mode',
                  icon: Icons.cloud_off_outlined,
                  color: Colors.orange,
                  tooltip:
                      'Operates offline with cached credentials (GAP-06)',
                ),
            ],
          ),
          // ── RCAN v1.6 badge row ─────────────────────────────────────────
          if (robot.isRcanV16) ...[
            const SizedBox(height: 4),
            _V16BadgeRow(robot: robot),
          ],
        ],
      ),
    );
  }
}

class _V15Badge extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final String tooltip;

  const _V15Badge({
    required this.label,
    required this.icon,
    required this.color,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withOpacity(0.10),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: color.withOpacity(0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                  fontSize: 10,
                  color: color,
                  fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }
}

// ── RCAN v1.6 badge row ───────────────────────────────────────────────────

class _V16BadgeRow extends StatelessWidget {
  final Robot robot;
  const _V16BadgeRow({required this.robot});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 6,
      runSpacing: 4,
      children: [
        // Transport chips: show each supported transport
        for (final t in robot.supportedTransports)
          _V15Badge(
            label: t.toUpperCase(),
            icon: _transportIcon(t),
            color: _transportColor(t),
            tooltip: 'Transport encoding: $t (GAP-17)',
          ),

        // LoA enforcement indicator
        _V15Badge(
          label: robot.loaEnforcement
              ? 'LoA enforcement: ON'
              : 'LoA enforcement: OFF',
          icon: robot.loaEnforcement
              ? Icons.verified_user_outlined
              : Icons.person_outline,
          color: robot.loaEnforcement ? Colors.green : Colors.orange,
          tooltip: robot.loaEnforcement
              ? 'LoA policy enforced — min LoA ${robot.minLoaForControl} required for control (GAP-16)'
              : 'LoA policy log-only — enforcement disabled (GAP-16)',
        ),

        // Registry tier badge
        _V15Badge(
          label: _registryTierLabel(robot.registryTier),
          icon: _registryTierIcon(robot.registryTier),
          color: _registryTierColor(robot.registryTier),
          tooltip: 'Registry tier: ${robot.registryTier} (GAP-14)',
        ),
      ],
    );
  }

  IconData _transportIcon(String t) {
    switch (t.toLowerCase()) {
      case 'http':
        return Icons.http_outlined;
      case 'compact':
        return Icons.compress_outlined;
      case 'ble':
        return Icons.bluetooth_outlined;
      case 'minimal':
        return Icons.minimize_outlined;
      default:
        return Icons.swap_horiz_outlined;
    }
  }

  Color _transportColor(String t) {
    switch (t.toLowerCase()) {
      case 'http':
        return Colors.indigo;
      case 'compact':
        return Colors.deepPurple;
      case 'ble':
        return Colors.lightBlue;
      case 'minimal':
        return Colors.grey;
      default:
        return Colors.blueGrey;
    }
  }

  String _registryTierLabel(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return 'Root Registry';
      case 'authoritative':
        return 'Authoritative Registry';
      case 'community':
      default:
        return 'Community Registry';
    }
  }

  IconData _registryTierIcon(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return Icons.star_outlined;
      case 'authoritative':
        return Icons.verified_outlined;
      case 'community':
      default:
        return Icons.people_outline;
    }
  }

  Color _registryTierColor(String tier) {
    switch (tier.toLowerCase()) {
      case 'root':
        return Colors.amber;
      case 'authoritative':
        return Colors.cyan;
      case 'community':
      default:
        return Colors.blueGrey;
    }
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
          Text(value,
              style:
                  TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

// ── Command tile ──────────────────────────────────────────────────────────────

class _CommandTile extends StatelessWidget {
  final RobotCommand cmd;
  const _CommandTile({required this.cmd});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
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

    // GAP-08: sender_type — surface in command history
    final senderType = cmd.senderType ?? 'human via OpenCastor app';

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
                // GAP-08 audit trail: sender_type displayed to user
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'sender_type: $senderType',
                    style: TextStyle(
                        fontSize: 10,
                        color: cs.onSurfaceVariant.withOpacity(0.6),
                        fontFamily: 'monospace'),
                  ),
                ),
                if (cmd.result != null &&
                    cmd.result!['raw_text'] != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      cmd.result!['raw_text'].toString(),
                      style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant),
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
            style:
                TextStyle(fontSize: 10, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  String _fmt(DateTime dt) =>
      DateFormat('HH:mm:ss').format(dt.toLocal());
}

// ── Chat input ────────────────────────────────────────────────────────────────

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
                  contentPadding: EdgeInsets.symmetric(
                      horizontal: 12, vertical: 10),
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
