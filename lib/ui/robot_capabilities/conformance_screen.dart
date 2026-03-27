/// Conformance sub-screen — full conformance score + breakdown.
/// Route: /robot/:rrn/capabilities/conformance
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../ui/core/theme/app_theme.dart';
import '../robot_detail/robot_detail_view_model.dart';
import 'capabilities_widgets.dart';

class ConformanceScreen extends ConsumerWidget {
  final String rrn;
  const ConformanceScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Conformance')),
          body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Conformance')),
              body: const Center(child: Text('Robot not found')));
        }
        return _ConformanceView(robot: robot);
      },
    );
  }
}

class _ConformanceView extends StatelessWidget {
  final Robot robot;
  const _ConformanceView({required this.robot});

  @override
  Widget build(BuildContext context) {
    final score = capConformanceScore(robot);
    final p66Pass = capP66PassCount(robot);
    return Scaffold(
      appBar: AppBar(title: Text('Conformance — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          ConformanceCard(robot: robot, score: score, p66Pass: p66Pass),
          const SizedBox(height: 16),
          _ScoreBreakdown(robot: robot, score: score, p66Pass: p66Pass),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

class _ScoreBreakdown extends StatelessWidget {
  final Robot robot;
  final int score;
  final int p66Pass;
  const _ScoreBreakdown(
      {required this.robot, required this.score, required this.p66Pass});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final items = [
      _BreakdownItem(
        label: 'ESTOP QoS (P66 §4)',
        points: 20,
        earned: robot.supportsQos2,
      ),
      _BreakdownItem(
        label: 'Replay Protection (RCAN v1.5)',
        points: 15,
        earned: robot.isRcanV15,
      ),
      _BreakdownItem(
        label: 'LoA Enforcement (GAP-16)',
        points: 15,
        earned: robot.loaEnforcement,
      ),
      _BreakdownItem(
        label: 'RCAN v2.2 (ML-DSA-65)',
        points: 10,
        earned: robot.isRcanV16,
      ),
      _BreakdownItem(
        label: 'RRN assigned',
        points: 10,
        earned: robot.rrn.isNotEmpty,
      ),
      _BreakdownItem(
        label: 'Vision capability',
        points: 10,
        earned: robot.hasCapability(RobotCapability.vision),
      ),
      _BreakdownItem(
        label: 'Registry verified+',
        points: 10,
        earned: () {
          final t = robot.registryTier.toLowerCase();
          return t == 'verified' || t == 'authoritative' || t == 'root';
        }(),
      ),
      _BreakdownItem(
        label: 'Offline mode',
        points: 5,
        earned: robot.offlineCapable,
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Icon(Icons.list_alt_outlined, size: 14, color: cs.primary),
          const SizedBox(width: 6),
          Text('Score Breakdown',
              style: Theme.of(context)
                  .textTheme
                  .labelLarge
                  ?.copyWith(color: cs.primary)),
        ]),
        const SizedBox(height: 8),
        Card(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (int i = 0; i < items.length; i++) ...[
                _BreakdownRow(item: items[i]),
                if (i < items.length - 1)
                  Divider(
                    height: 1,
                    indent: 16,
                    endIndent: 16,
                    color: cs.outlineVariant.withOpacity(0.4),
                  ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

class _BreakdownItem {
  final String label;
  final int points;
  final bool earned;
  const _BreakdownItem(
      {required this.label, required this.points, required this.earned});
}

class _BreakdownRow extends StatelessWidget {
  final _BreakdownItem item;
  const _BreakdownRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          Icon(
            item.earned
                ? Icons.check_circle_outline
                : Icons.radio_button_unchecked,
            size: 16,
            color: item.earned ? AppTheme.online : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(item.label,
                style: TextStyle(
                    fontSize: 13,
                    color: item.earned
                        ? cs.onSurface
                        : cs.onSurfaceVariant)),
          ),
          Text(
            item.earned ? '+${item.points}' : '—',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: item.earned
                  ? AppTheme.online
                  : cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}
