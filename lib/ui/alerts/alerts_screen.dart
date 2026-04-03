/// Alerts Screen — shows ESTOP events, faults, and system alerts per robot.
///
/// MVVM: data flows through [fleetProvider] + [alertsProvider] (data layer).
/// No direct Firestore calls from build().
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;

import '../../data/models/robot.dart';
import '../../ui/core/theme/app_theme.dart';
import '../fleet/fleet_view_model.dart' show fleetProvider;
import 'alerts_view_model.dart';
import '../shared/error_view.dart';
import '../shared/loading_view.dart';


// ── Screen ────────────────────────────────────────────────────────────────────

class AlertsScreen extends ConsumerWidget {
  const AlertsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleetAsync = ref.watch(fleetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Alerts'),
      ),
      body: fleetAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (robots) {
          if (robots.isEmpty) {
            return const _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(fleetProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: robots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) => _RobotAlertSection(robot: robots[i]),
            ),
          );
        },
      ),
    );
  }
}

// ── Robot section ─────────────────────────────────────────────────────────────

class _RobotAlertSection extends ConsumerWidget {
  final Robot robot;
  const _RobotAlertSection({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alertsAsync = ref.watch(alertsProvider(robot.rrn));
    final cs = Theme.of(context).colorScheme;

    return Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Robot header ──────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Icon(
                  Icons.precision_manufacturing_outlined,
                  size: 16,
                  color: cs.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    robot.name,
                    style: Theme.of(context)
                        .textTheme
                        .titleSmall
                        ?.copyWith(fontWeight: FontWeight.bold),
                  ),
                ),
                // Online dot
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: robot.isOnline ? AppTheme.online : AppTheme.offline,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  robot.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                    fontSize: 11,
                    color: robot.isOnline ? AppTheme.online : AppTheme.offline,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),

          // ── Alerts ────────────────────────────────────────────────────
          alertsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(child: LinearProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                'Error loading alerts',
                style: TextStyle(color: cs.error, fontSize: 12),
              ),
            ),
            data: (alerts) {
              if (alerts.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppTheme.online,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'No recent alerts',
                        style: TextStyle(
                          fontSize: 12,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return Column(
                children: alerts.map((a) => _AlertTile(alert: a)).toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ── Alert tile ────────────────────────────────────────────────────────────────

class _AlertTile extends StatelessWidget {
  final Map<String, dynamic> alert;
  const _AlertTile({required this.alert});

  @override
  Widget build(BuildContext context) {
    final type = alert['type'] as String? ?? 'UNKNOWN';
    final reason = alert['reason'] as String? ?? '';
    final firedAtStr = alert['fired_at'] as String?;
    final firedAt =
        firedAtStr != null ? DateTime.tryParse(firedAtStr) : null;

    final isEstop = type == 'ESTOP';
    final color = isEstop ? AppTheme.estop : AppTheme.warning;
    final icon = isEstop
        ? Icons.stop_circle_outlined
        : Icons.warning_amber_outlined;

    return ListTile(
      dense: true,
      leading: Semantics(
        label: type,
        child: ExcludeSemantics(
          child: Icon(icon, color: color, size: 20),
        ),
      ),
      title: Text(
        type,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: color,
          fontSize: 13,
        ),
      ),
      subtitle: reason.isNotEmpty
          ? Text(reason, style: const TextStyle(fontSize: 12))
          : null,
      trailing: firedAt != null
          ? Text(
              timeago.format(firedAt),
              style: TextStyle(
                fontSize: 11,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            )
          : null,
    );
  }
}

// ── Empty / error states ──────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.notifications_none_outlined,
            size: 64,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('No robots in fleet',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Alerts will appear here once you add robots to your fleet.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}


