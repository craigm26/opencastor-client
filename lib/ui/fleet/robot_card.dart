import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../../ui/core/widgets/capability_badge.dart';
import '../../ui/core/widgets/health_indicator.dart';
import '../../ui/core/widgets/confirmation_dialog.dart';

class RobotCard extends StatelessWidget {
  final Robot robot;
  final VoidCallback onTap;
  final VoidCallback? onControl;
  final Future<void> Function()? onEstop;

  const RobotCard({
    super.key,
    required this.robot,
    required this.onTap,
    this.onControl,
    this.onEstop,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final last = robot.status.lastSeen;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header row: name + status dot
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          robot.name,
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          robot.rrn,
                          style: AppTheme.mono.copyWith(
                            fontSize: 11,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  HealthIndicator(isOnline: robot.isOnline, lastSeen: last),
                ],
              ),
              const SizedBox(height: 12),

              // Capabilities
              if (robot.capabilities.isNotEmpty) ...[
                CapabilityRow(capabilities: robot.capabilities),
                const SizedBox(height: 10),
              ],

              // Telemetry chips
              _TelemetryRow(telemetry: robot.telemetry),
              const SizedBox(height: 12),

              // Footer: last seen + action buttons
              Row(
                children: [
                  Icon(Icons.access_time, size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    timeago.format(last),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
                  ),
                  const Spacer(),
                  // Control button (only if robot has control capability)
                  if (robot.hasCapability(RobotCapability.control) &&
                      onControl != null)
                    _ActionBtn(
                      icon: Icons.precision_manufacturing_outlined,
                      label: 'Control',
                      onTap: onControl!,
                      enabled: robot.isOnline,
                    ),
                  const SizedBox(width: 8),
                  // ESTOP — always visible if online
                  if (robot.isOnline && onEstop != null)
                    _EstopBtn(robotName: robot.name, onEstop: onEstop!),
                ],
              ),
            ],
          ),
        ),
      ),
    ).animate().fadeIn(duration: 250.ms).slideY(begin: 0.05, end: 0);
  }
}

class _TelemetryRow extends StatelessWidget {
  final Map<String, dynamic> telemetry;
  const _TelemetryRow({required this.telemetry});

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[];

    final temp = telemetry['cpu_temp'] ?? telemetry['temperature'];
    if (temp != null) {
      chips.add(_TelChip(
        icon: Icons.thermostat_outlined,
        label: '${temp.toStringAsFixed(0)}°C',
        color: (temp as num) > 70 ? AppTheme.warning : null,
      ));
    }

    final disk = telemetry['disk_pct'] ?? telemetry['disk_used_pct'];
    if (disk != null) {
      chips.add(_TelChip(
        icon: Icons.storage_outlined,
        label: '${(disk as num).toStringAsFixed(0)}%',
        color: (disk as num) > 85 ? AppTheme.warning : null, // ignore: unnecessary_cast
      ));
    }

    final version = telemetry['version'] ?? telemetry['opencastor_version'];
    if (version != null) {
      chips.add(_TelChip(
        icon: Icons.tag_outlined,
        label: version.toString(),
      ));
    }

    if (chips.isEmpty) return const SizedBox.shrink();

    return Wrap(spacing: 8, runSpacing: 4, children: chips);
  }
}

class _TelChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;
  const _TelChip({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = color ?? cs.onSurfaceVariant;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: fg),
        const SizedBox(width: 3),
        Text(label, style: TextStyle(fontSize: 11, color: fg)),
      ],
    );
  }
}

class _ActionBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool enabled;
  const _ActionBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return FilledButton.tonalIcon(
      onPressed: enabled ? onTap : null,
      icon: Icon(icon, size: 14),
      label: Text(label, style: const TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}

class _EstopBtn extends StatelessWidget {
  final String robotName;
  final Future<void> Function() onEstop;
  const _EstopBtn({required this.robotName, required this.onEstop});

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      onPressed: () async {
        final confirmed = await showEstopDialog(context, robotName);
        if (confirmed) await onEstop();
      },
      icon: const Icon(Icons.stop_circle_outlined, size: 14),
      label: const Text('ESTOP', style: TextStyle(fontSize: 12)),
      style: FilledButton.styleFrom(
        backgroundColor: AppTheme.estop,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 10),
      ),
    );
  }
}
