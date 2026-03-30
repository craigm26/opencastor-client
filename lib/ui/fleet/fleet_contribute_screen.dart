/// Fleet-wide contribution dashboard (#11).
///
/// Shows aggregate contribution stats across all robots the user owns.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../fleet_contribute/credits_card.dart';
import '../shared/pipeline_explainer.dart';
import '../shared/error_view.dart';
import '../shared/loading_view.dart';

/// Aggregate fleet contribution stats.
class _FleetContributeStats {
  final int totalRobots;
  final int contributingRobots;
  final int totalMinutesToday;
  final int totalMinutesLifetime;
  final int totalWorkUnits;
  final List<_RobotContribute> robots;

  const _FleetContributeStats({
    required this.totalRobots,
    required this.contributingRobots,
    required this.totalMinutesToday,
    required this.totalMinutesLifetime,
    required this.totalWorkUnits,
    required this.robots,
  });
}

class _RobotContribute {
  final String rrn;
  final String name;
  final bool enabled;
  final bool active;
  final String project;
  final int minutesToday;
  final int workUnitsTotal;

  const _RobotContribute({
    required this.rrn,
    required this.name,
    required this.enabled,
    required this.active,
    required this.project,
    required this.minutesToday,
    required this.workUnitsTotal,
  });
}

final _fleetContributeProvider =
    FutureProvider<_FleetContributeStats>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    return const _FleetContributeStats(
      totalRobots: 0,
      contributingRobots: 0,
      totalMinutesToday: 0,
      totalMinutesLifetime: 0,
      totalWorkUnits: 0,
      robots: [],
    );
  }

  final snap = await FirebaseFirestore.instance
      .collection('robots')
      .where('owner_uid', isEqualTo: uid)
      .get();

  final robots = <_RobotContribute>[];
  int totalMinToday = 0;
  int totalMinLifetime = 0;
  int totalWU = 0;
  int contributing = 0;

  for (final doc in snap.docs) {
    final data = doc.data();
    final telemetry = data['telemetry'] as Map<String, dynamic>? ?? {};
    final contribute = telemetry['contribute'] as Map<String, dynamic>? ??
        (data['contribute'] as Map<String, dynamic>? ?? {});

    final enabled = contribute['enabled'] as bool? ?? false;
    final active = contribute['active'] as bool? ?? false;
    final minToday =
        (contribute['contribute_minutes_today'] as num?)?.toInt() ?? 0;
    final minLifetime =
        (contribute['contribute_minutes_lifetime'] as num?)?.toInt() ?? 0;
    final wu = (contribute['work_units_total'] as num?)?.toInt() ?? 0;

    if (enabled) contributing++;
    totalMinToday += minToday;
    totalMinLifetime += minLifetime;
    totalWU += wu;

    robots.add(_RobotContribute(
      rrn: doc.id,
      name: (data['metadata'] as Map<String, dynamic>?)?['robot_name']
              as String? ??
          doc.id,
      enabled: enabled,
      active: active,
      project: contribute['project'] as String? ?? '—',
      minutesToday: minToday,
      workUnitsTotal: wu,
    ));
  }

  // Sort: active first, then by work units
  robots.sort((a, b) {
    if (a.active != b.active) return a.active ? -1 : 1;
    if (a.enabled != b.enabled) return a.enabled ? -1 : 1;
    return b.workUnitsTotal.compareTo(a.workUnitsTotal);
  });

  return _FleetContributeStats(
    totalRobots: snap.docs.length,
    contributingRobots: contributing,
    totalMinutesToday: totalMinToday,
    totalMinutesLifetime: totalMinLifetime,
    totalWorkUnits: totalWU,
    robots: robots,
  );
});

class FleetContributeScreen extends ConsumerWidget {
  const FleetContributeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statsAsync = ref.watch(_fleetContributeProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Fleet Contribution')),
      body: statsAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
        data: (stats) {
          if (stats.totalRobots == 0) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.dns_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('No robots found',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(_fleetContributeProvider),
            child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              // Pipeline explainer — always at top
              const PipelineExplainer(mode: ContributeMode.community),
              const SizedBox(height: 16),
              // Credits card
              const CreditsCard(),
              const SizedBox(height: 16),

              // Summary cards
              Row(
                children: [
                  Expanded(
                      child: _StatCard(
                    label: 'Contributing',
                    value: '${stats.contributingRobots}/${stats.totalRobots}',
                    icon: Icons.science_outlined,
                    color: theme.colorScheme.primary,
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatCard(
                    label: 'Today',
                    value: _fmtMinutes(stats.totalMinutesToday),
                    icon: Icons.today_outlined,
                    color: theme.colorScheme.secondary,
                  )),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                      child: _StatCard(
                    label: 'Lifetime',
                    value: _fmtMinutes(stats.totalMinutesLifetime),
                    icon: Icons.all_inclusive_outlined,
                    color: theme.colorScheme.tertiary,
                  )),
                  const SizedBox(width: 12),
                  Expanded(
                      child: _StatCard(
                    label: 'Work Units',
                    value: _fmtNumber(stats.totalWorkUnits),
                    icon: Icons.memory_outlined,
                    color: theme.colorScheme.primary,
                  )),
                ],
              ),
              const SizedBox(height: 24),

              // Leaderboard entry point
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.leaderboard_outlined),
                  title: const Text('View Fleet Leaderboard'),
                  subtitle: const Text('Ranked by contribution score'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => context.push('/fleet/leaderboard'),
                ),
              ),
              const SizedBox(height: 24),

              // Per-robot list
              Text('Robots',
                  style: theme.textTheme.titleMedium
                      ?.copyWith(fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),
              ...stats.robots.map((r) => Card(
                    margin: const EdgeInsets.only(bottom: 8),
                    child: ListTile(
                      leading: CircleAvatar(
                        backgroundColor: r.active
                            ? Colors.green.withValues(alpha: 0.15)
                            : r.enabled
                                ? Colors.orange.withValues(alpha: 0.15)
                                : theme.colorScheme.surfaceContainerHighest,
                        child: Icon(
                          r.active
                              ? Icons.play_circle_filled
                              : r.enabled
                                  ? Icons.pause_circle_outline
                                  : Icons.circle_outlined,
                          color: r.active
                              ? Colors.green
                              : r.enabled
                                  ? Colors.orange
                                  : theme.colorScheme.outline,
                          size: 24,
                        ),
                      ),
                      title: Text(r.name),
                      subtitle: Text(
                        r.active
                            ? 'Active · ${r.project} · ${_fmtMinutes(r.minutesToday)} today'
                            : r.enabled
                                ? 'Enabled · idle · ${r.workUnitsTotal} units lifetime'
                                : 'Disabled',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                      trailing: Text(
                        _fmtNumber(r.workUnitsTotal),
                        style: theme.textTheme.labelLarge,
                      ),
                    ),
                  )),

              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.workspace_premium_outlined),
                  label: const Text('Go Pro'),
                  onPressed: () => context.push('/pro'),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
          );
        },
      ),
    );
  }

  static String _fmtMinutes(int m) {
    if (m == 0) return '0m';
    if (m < 60) return '${m}m';
    if (m < 1440) return '${m ~/ 60}h ${m % 60}m';
    return '${m ~/ 1440}d ${(m % 1440) ~/ 60}h';
  }

  static String _fmtNumber(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }
}

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 20, color: color),
            const SizedBox(height: 8),
            Text(value,
                style: theme.textTheme.headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }
}
