/// ResearchScreen — per-robot research runs, personal best, and community
/// submission for the OHB-1 benchmark.
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/personal_research.dart';
import '../../data/services/personal_research_service.dart';
import '../fleet_leaderboard/personal_research_card.dart';
import '../fleet_leaderboard/personal_research_view_model.dart';
import '../shared/loading_view.dart';

class ResearchScreen extends ConsumerStatefulWidget {
  final String rrn;
  const ResearchScreen({super.key, required this.rrn});

  @override
  ConsumerState<ResearchScreen> createState() => _ResearchScreenState();
}

class _ResearchScreenState extends ConsumerState<ResearchScreen> {
  bool _running = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final summaryAsync = ref.watch(personalResearchRrnProvider(widget.rrn));

    return Scaffold(
      backgroundColor: cs.surface,
      appBar: AppBar(
        title: Text(
          'Research',
          style: theme.textTheme.titleMedium?.copyWith(
            fontFamily: 'Space Grotesk',
            fontWeight: FontWeight.w600,
          ),
        ),
        centerTitle: false,
        backgroundColor: cs.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () => ref.invalidate(personalResearchRrnProvider(widget.rrn)),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 32),
        children: [
          // Header blurb
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              'Run the OHB-1 benchmark on this robot and submit your best score '
              'to the community leaderboard.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'Inter',
              ),
            ),
          ),

          const SizedBox(height: 8),

          // Personal research full card (scoped to this RRN)
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: const LoadingView(),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                'Could not load research data: $e',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: cs.error,
                  fontFamily: 'Inter',
                ),
              ),
            ),
            data: (summary) => _ResearchBody(
              rrn: widget.rrn,
              summary: summary,
              running: _running,
              onRun: () => _triggerRun(context),
              onSubmit: summary?.bestRun != null
                  ? () => _submitRun(context, ref, summary!)
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _triggerRun(BuildContext context) async {
    if (_running) return;
    setState(() => _running = true);
    try {
      final ok = await PersonalResearchService().triggerRun(widget.rrn);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ok
              ? 'Research run queued — bridge will process shortly'
              : 'Could not queue run — check robot connection'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      if (ok) {
        await Future.delayed(const Duration(seconds: 8));
        if (mounted) ref.invalidate(personalResearchRrnProvider(widget.rrn));
      }
    } finally {
      if (mounted) setState(() => _running = false);
    }
  }

  Future<void> _submitRun(
    BuildContext context,
    WidgetRef ref,
    PersonalResearchSummary summary,
  ) async {
    final run = summary.bestRun;
    if (run == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Submit for community verification?'),
        content: Text(
          'Your result (${run.score.toStringAsFixed(4)}) will be verified with '
          '3 independent runs.\n\nIf confirmed, you\'ll earn credits and appear '
          'on the community leaderboard.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Submit'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final ok = await PersonalResearchService()
        .submitToCommunity(widget.rrn, run.runId);

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
    if (ok) ref.invalidate(personalResearchRrnProvider(widget.rrn));
  }
}

// ── Research body ─────────────────────────────────────────────────────────────

class _ResearchBody extends StatelessWidget {
  final String rrn;
  final PersonalResearchSummary? summary;
  final VoidCallback onRun;
  final VoidCallback? onSubmit;
  final bool running;

  const _ResearchBody({
    required this.rrn,
    required this.summary,
    required this.running,
    required this.onRun,
    this.onSubmit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final best = summary?.bestRun;
    final totalRuns = summary?.totalRuns ?? 0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Stats row
          Row(
            children: [
              _StatChip(
                label: 'Runs',
                value: '$totalRuns',
                color: cs.primary,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'Best score',
                value: best != null
                    ? best.score.toStringAsFixed(4)
                    : '—',
                color: cs.secondary,
              ),
              const SizedBox(width: 8),
              _StatChip(
                label: 'RRN',
                value: rrn.replaceFirst('RRN-', '#'),
                color: cs.tertiary,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Run button
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              icon: running
                  ? const SizedBox(
                      width: 18, height: 18,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white))
                  : const Icon(Icons.play_arrow_rounded),
              label: Text(running ? 'Queuing run…' : 'Run OHB-1 Benchmark'),
              onPressed: running ? null : onRun,
            ),
          ),

          // Submit CTA
          if (onSubmit != null) ...[
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.upload_outlined),
                label: const Text('Submit to Community →'),
                onPressed: onSubmit,
              ),
            ),
          ],

          const SizedBox(height: 24),

          // Run history (if any)
          if (best != null) ...[
            Text(
              'Personal Best',
              style: theme.textTheme.labelMedium?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w600,
                letterSpacing: 0.5,
              ),
            ),
            const SizedBox(height: 8),
            _RunTile(run: best, isHighlighted: true),
          ] else ...[
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: cs.surfaceContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.science_outlined,
                      size: 20, color: cs.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Text(
                    'No runs yet — tap Run to start benchmarking.',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'Inter',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _StatChip({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              value,
              style: theme.textTheme.titleSmall?.copyWith(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'Inter',
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RunTile extends StatelessWidget {
  final PersonalRun run;
  final bool isHighlighted;
  const _RunTile({required this.run, this.isHighlighted = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isHighlighted
            ? cs.primaryContainer.withValues(alpha: 0.4)
            : cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: isHighlighted
            ? Border.all(color: cs.primary.withValues(alpha: 0.4))
            : null,
      ),
      child: Row(
        children: [
          if (isHighlighted)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Icon(Icons.star_rounded, size: 14, color: cs.primary),
            ),
          Expanded(
            child: Text(
              run.candidateId,
              style: theme.textTheme.bodySmall?.copyWith(
                fontFamily: 'Space Grotesk',
                fontWeight: FontWeight.w500,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            run.score.toStringAsFixed(4),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontFamily: 'Space Grotesk',
              fontWeight: FontWeight.w700,
              color: isHighlighted ? cs.primary : cs.onSurface,
            ),
          ),
          if (run.createdAt != null) ...[
            const SizedBox(width: 8),
            Text(
              _timeAgo(run.createdAt!),
              style: theme.textTheme.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontFamily: 'Inter',
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
