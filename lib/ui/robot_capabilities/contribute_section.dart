/// Contribute section for the Robot Capabilities screen.
///
/// Shows idle compute donation status from telemetry.contribute.
library;

import 'package:flutter/material.dart';

import '../../data/models/robot.dart';

/// Format minutes as human-readable string.
String _formatMinutes(int m) {
  if (m == 0) return '—';
  if (m < 60) return '$m min';
  return '${m ~/ 60}h ${m % 60}m';
}

class ContributeSection extends StatelessWidget {
  final ContributeStats stats;

  const ContributeSection({super.key, required this.stats});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Status indicator
    final Color statusColor;
    final String statusLabel;
    final IconData statusIcon;

    if (!stats.enabled) {
      statusColor = colorScheme.outline;
      statusLabel = 'Disabled';
      statusIcon = Icons.volunteer_activism_outlined;
    } else if (stats.active) {
      statusColor = Colors.green;
      statusLabel = 'Active';
      statusIcon = Icons.volunteer_activism;
    } else {
      statusColor = Colors.orange;
      statusLabel = 'Enabled (idle)';
      statusIcon = Icons.volunteer_activism_outlined;
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Icon(Icons.volunteer_activism_outlined,
                    size: 20, color: colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Idle Compute Contribution',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 12, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: statusColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            if (!stats.enabled) ...[
              // Enable hint
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.info_outline,
                        size: 16, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Enable in robot config:\nagent.contribute.enabled: true',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ] else ...[
              // Stats grid
              Row(
                children: [
                  Expanded(
                    child: _StatTile(
                      label: 'Today',
                      value: _formatMinutes(stats.contributeMinutesToday),
                      icon: Icons.today_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      label: 'Lifetime',
                      value: _formatMinutes(stats.contributeMinutesLifetime),
                      icon: Icons.history_outlined,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _StatTile(
                      label: 'Work Units',
                      value: stats.workUnitsTotal > 0
                          ? stats.workUnitsTotal.toString()
                          : '—',
                      icon: Icons.task_alt_outlined,
                    ),
                  ),
                ],
              ),
              if (stats.project != null) ...[
                const SizedBox(height: 10),
                Row(
                  children: [
                    Icon(Icons.science_outlined,
                        size: 14, color: colorScheme.onSurfaceVariant),
                    const SizedBox(width: 6),
                    Text(
                      'Project: ${stats.project}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ],
            ],
          ],
        ),
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _StatTile(
      {required this.label, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Icon(icon, size: 16, color: theme.colorScheme.primary),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
