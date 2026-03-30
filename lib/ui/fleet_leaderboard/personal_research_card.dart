/// PersonalResearchCard — shows the user's personal research best run and
/// a "Submit to Community" CTA when their score beats the community champion.
///
/// Also exports [PersonalResearchMiniCard] for compact use on robot detail.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/personal_research.dart';
import '../../data/services/personal_research_service.dart';
import 'personal_research_view_model.dart';

// ── Full card ─────────────────────────────────────────────────────────────────

/// Full personal research card shown at the top of the Compete / Leaderboard tab.
class PersonalResearchCard extends ConsumerWidget {
  /// Score of the current community champion (used to gate the Submit button).
  final double communityChampionScore;

  const PersonalResearchCard({
    super.key,
    this.communityChampionScore = 0.0,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(personalResearchProvider);

    return summaryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (summary) => _PersonalResearchCardBody(
        summary: summary,
        communityChampionScore: communityChampionScore,
        onRun: () => _onRun(context, ref),
        onSubmit: summary?.bestRun != null
            ? () => _onSubmit(context, ref, summary!.bestRun!)
            : null,
      ),
    );
  }

  Future<void> _onRun(BuildContext context, WidgetRef ref) async {
    final rrn = await ref.read(userRrnProvider.future);
    if (rrn == null) return;
    // Fire-and-forget — show snackbar immediately per UX spec.
    PersonalResearchService().triggerRun(rrn);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Personal run queued — results in ~60s'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _onSubmit(
    BuildContext context,
    WidgetRef ref,
    PersonalRun run,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => _SubmitConfirmDialog(run: run),
    );
    if (confirmed != true) return;

    final rrn = await ref.read(userRrnProvider.future);
    if (rrn == null) return;
    final ok = await PersonalResearchService().submitToCommunity(rrn, run.runId);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Submitted for verification — check back soon!'
              : 'Submission failed. Please try again.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    if (ok) ref.invalidate(personalResearchProvider);
  }
}

// ── Card body ─────────────────────────────────────────────────────────────────

class _PersonalResearchCardBody extends StatelessWidget {
  final PersonalResearchSummary? summary;
  final double communityChampionScore;
  final VoidCallback onRun;
  final VoidCallback? onSubmit;

  const _PersonalResearchCardBody({
    required this.summary,
    required this.communityChampionScore,
    required this.onRun,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final best = summary?.bestRun;
    final totalRuns = summary?.totalRuns ?? 0;
    final showSubmit =
        best != null && best.score > communityChampionScore && onSubmit != null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row
          Row(
            children: [
              Text(
                '🔬 My Research',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontFamily: 'Space Grotesk',
                  fontWeight: FontWeight.w600,
                ),
              ),
              const Spacer(),
              FilledButton.tonalIcon(
                icon: const Icon(Icons.play_arrow, size: 16),
                label: const Text('Run'),
                style: FilledButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                ),
                onPressed: onRun,
              ),
            ],
          ),
          const SizedBox(height: 12),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // Body — personal best or empty state
          if (best != null) ...[
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            'Personal best: ',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: 'Inter',
                            ),
                          ),
                          Text(
                            best.score.toStringAsFixed(4),
                            style: theme.textTheme.bodyMedium?.copyWith(
                              fontFamily: 'Space Grotesk',
                              fontWeight: FontWeight.w700,
                              color: cs.primary,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            best.candidateId,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: cs.onSurfaceVariant,
                              fontFamily: 'Inter',
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (best.createdAt != null) ...[
                            const SizedBox(width: 6),
                            Text(
                              _timeAgo(best.createdAt!),
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '$totalRuns ${totalRuns == 1 ? 'run' : 'runs'} total',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else ...[
            Text(
              totalRuns > 0
                  ? '$totalRuns ${totalRuns == 1 ? 'run' : 'runs'} — no best recorded yet'
                  : 'No runs yet. Hit Run ▶ to start.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'Inter',
              ),
            ),
          ],

          // Submit CTA — only when beating community champion
          if (showSubmit) ...[
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_outlined, size: 16),
                label: const Text('Submit to Community →'),
                onPressed: onSubmit,
              ),
            ),
          ],
        ],
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}

// ── Submit confirmation dialog ────────────────────────────────────────────────

class _SubmitConfirmDialog extends StatelessWidget {
  final PersonalRun run;
  const _SubmitConfirmDialog({required this.run});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Submit for community verification?'),
      content: Text(
        'Your result (${run.score.toStringAsFixed(4)}) will be verified with '
        '3 independent runs.\n\nIf confirmed, you\'ll earn credits and appear '
        'on the community leaderboard.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Submit'),
        ),
      ],
    );
  }
}

// ── Mini card (robot detail screen) ──────────────────────────────────────────

/// Compact personal research strip shown at the bottom of robot detail.
class PersonalResearchMiniCard extends ConsumerWidget {
  final String rrn;
  const PersonalResearchMiniCard({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summaryAsync = ref.watch(personalResearchRrnProvider(rrn));

    return summaryAsync.when(
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
      data: (summary) {
        final best = summary?.bestRun;
        final totalRuns = summary?.totalRuns ?? 0;
        if (summary == null && totalRuns == 0) return const SizedBox.shrink();
        return _MiniCardBody(
          rrn: rrn,
          best: best,
          totalRuns: totalRuns,
          lastRunAt: summary?.lastRunAt,
          onRun: () => _onRun(context, ref),
        );
      },
    );
  }

  Future<void> _onRun(BuildContext context, WidgetRef ref) async {
    PersonalResearchService().triggerRun(rrn);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Personal run queued — results in ~60s'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
    ref.invalidate(personalResearchRrnProvider(rrn));
  }
}

class _MiniCardBody extends StatelessWidget {
  final String rrn;
  final PersonalRun? best;
  final int totalRuns;
  final DateTime? lastRunAt;
  final VoidCallback onRun;

  const _MiniCardBody({
    required this.rrn,
    required this.best,
    required this.totalRuns,
    required this.lastRunAt,
    required this.onRun,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    final parts = <String>[];
    if (best != null) parts.add('Best ${best!.score.toStringAsFixed(4)}');
    if (totalRuns > 0) parts.add('$totalRuns ${totalRuns == 1 ? 'run' : 'runs'}');
    if (lastRunAt != null) parts.add('Last ${_timeAgo(lastRunAt!)}');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          const Text('🔬', style: TextStyle(fontSize: 14)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'My Best Run',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontFamily: 'Space Grotesk',
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (parts.isNotEmpty)
                  Text(
                    parts.join('  ·  '),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'Inter',
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
              ],
            ),
          ),
          TextButton(
            onPressed: onRun,
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
            ),
            child: const Text('Run Now'),
          ),
        ],
      ),
    );
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
