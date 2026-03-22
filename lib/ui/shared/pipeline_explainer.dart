/// PipelineExplainer — end-to-end "How it works" widget for contribute flows.
///
/// Shows a collapsible step-by-step pipeline for either:
///   - private fleet research (run_type=personal): private results, no credits
///   - community research (run_type=community): champion promoted, credits earned
///
/// Designed to be embedded anywhere contribute context is shown:
///   - CapContributeScreen (robot capabilities → contribute)
///   - FeaturedProjectCard (Compete tab → Research Projects)
///   - FleetContributeScreen (fleet-wide contribute dashboard)
library;

import 'package:flutter/material.dart';

enum ContributeMode { personal, community }

class PipelineExplainer extends StatefulWidget {
  /// Which pipeline variant to show.
  final ContributeMode mode;

  /// Start expanded. Defaults to false (collapsed).
  final bool initiallyExpanded;

  const PipelineExplainer({
    super.key,
    this.mode = ContributeMode.community,
    this.initiallyExpanded = false,
  });

  @override
  State<PipelineExplainer> createState() => _PipelineExplainerState();
}

class _PipelineExplainerState extends State<PipelineExplainer>
    with SingleTickerProviderStateMixin {
  late bool _expanded;
  late AnimationController _controller;
  late Animation<double> _expand;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _controller = AnimationController(
      duration: const Duration(milliseconds: 220),
      vsync: this,
      value: _expanded ? 1.0 : 0.0,
    );
    _expand = CurvedAnimation(parent: _controller, curve: Curves.easeInOut);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    _expanded ? _controller.forward() : _controller.reverse();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isCommunity = widget.mode == ContributeMode.community;
    const cyan = Color(0xFF55d7ed);
    const amber = Color(0xFFffba38);

    final accentColor = isCommunity ? cyan : cs.onSurfaceVariant;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.15),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (always visible, tappable) ──────────────────────────────
          InkWell(
            onTap: _toggle,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                children: [
                  Icon(Icons.route_outlined, size: 14, color: accentColor),
                  const SizedBox(width: 6),
                  Text(
                    'How it works',
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: accentColor,
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Space Grotesk',
                      letterSpacing: 0.3,
                    ),
                  ),
                  if (isCommunity) ...[
                    const SizedBox(width: 8),
                    _MiniChip(
                      label: 'Earn Credits',
                      color: amber,
                    ),
                  ],
                  const Spacer(),
                  AnimatedRotation(
                    turns: _expanded ? 0.25 : 0,
                    duration: const Duration(milliseconds: 200),
                    child: Icon(Icons.chevron_right,
                        size: 16, color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          // ── Expandable step flow ────────────────────────────────────────────
          SizeTransition(
            sizeFactor: _expand,
            child: Column(
              children: [
                Divider(height: 1, color: cs.outlineVariant.withValues(alpha: 0.3)),
                const SizedBox(height: 12),
                _PipelineSteps(mode: widget.mode),
                const SizedBox(height: 12),
                _PipelineSummary(mode: widget.mode),
                const SizedBox(height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Step data ─────────────────────────────────────────────────────────────────

class _Step {
  final IconData icon;
  final String label;
  final String detail;
  final bool isHighlight; // amber accent (champion step)

  const _Step({
    required this.icon,
    required this.label,
    required this.detail,
    this.isHighlight = false,
  });
}

List<_Step> _stepsFor(ContributeMode mode) {
  final shared = [
    const _Step(
      icon: Icons.bedtime_outlined,
      label: 'Robot idle',
      detail: 'Contribution starts only when your robot has no active tasks',
    ),
    const _Step(
      icon: Icons.download_outlined,
      label: 'Fetch config',
      detail: 'A candidate harness configuration is pulled from the research queue',
    ),
    const _Step(
      icon: Icons.bolt_outlined,
      label: 'Run 30 tasks',
      detail: 'Robot evaluates the config against OHB-1 benchmark — 30 real robotics scenarios',
    ),
    const _Step(
      icon: Icons.upload_outlined,
      label: 'Submit score',
      detail: 'Score is recorded: task success, P66 safety, cost efficiency, latency',
    ),
  ];

  if (mode == ContributeMode.personal) {
    return [
      ...shared,
      const _Step(
        icon: Icons.lock_outlined,
        label: 'Private results',
        detail: 'Your scores stay private. Insights improve your fleet only — not shared publicly',
      ),
    ];
  } else {
    return [
      ...shared,
      const _Step(
        icon: Icons.emoji_events_outlined,
        label: 'Champion available',
        detail:
            'Nightly: best score wins. Champion config is stored as a pending update — '
            'you choose when to apply it to each robot or the full fleet.',
        isHighlight: true,
      ),
    ];
  }
}

// ── Step renderer ─────────────────────────────────────────────────────────────

class _PipelineSteps extends StatelessWidget {
  final ContributeMode mode;
  const _PipelineSteps({required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const cyan = Color(0xFF55d7ed);
    const amber = Color(0xFFffba38);
    final steps = _stepsFor(mode);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Column(
        children: [
          for (var i = 0; i < steps.length; i++) ...[
            _StepRow(
              step: steps[i],
              number: i + 1,
              accentColor: steps[i].isHighlight ? amber : cyan,
              theme: theme,
              cs: cs,
            ),
            if (i < steps.length - 1)
              Padding(
                padding: const EdgeInsets.only(left: 18),
                child: SizedBox(
                  height: 14,
                  child: VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: cs.outlineVariant.withValues(alpha: 0.4),
                  ),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final _Step step;
  final int number;
  final Color accentColor;
  final ThemeData theme;
  final ColorScheme cs;

  const _StepRow({
    required this.step,
    required this.number,
    required this.accentColor,
    required this.theme,
    required this.cs,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Step indicator circle
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            shape: BoxShape.circle,
            border: Border.all(
              color: accentColor.withValues(alpha: 0.4),
              width: 1,
            ),
          ),
          child: Center(
            child: Icon(step.icon, size: 14, color: accentColor),
          ),
        ),
        const SizedBox(width: 10),
        // Step label + detail
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '$number. ${step.label}',
                    style: theme.textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontFamily: 'Space Grotesk',
                      color: step.isHighlight ? accentColor : cs.onSurface,
                    ),
                  ),
                  if (step.isHighlight) ...[
                    const SizedBox(width: 6),
                    _MiniChip(label: 'You earn credits', color: accentColor),
                  ],
                ],
              ),
              const SizedBox(height: 2),
              Text(
                step.detail,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Summary footer ────────────────────────────────────────────────────────────

class _PipelineSummary extends StatelessWidget {
  final ContributeMode mode;
  const _PipelineSummary({required this.mode});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final isCommunity = mode == ContributeMode.community;

    final icon = isCommunity ? Icons.public_outlined : Icons.lock_outlined;
    final text = isCommunity
        ? 'Your robot searches for the best AI agent harness config. '
          'When a new champion is found, it\'s stored as a pending update — '
          'you apply it to individual robots or the full fleet on your own schedule.'
        : 'Your robot\'s research stays private. Scores improve your fleet\'s harness '
          'without contributing to the community leaderboard or earning credits.';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 14, color: cs.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                text,
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Shared mini chip ──────────────────────────────────────────────────────────

class _MiniChip extends StatelessWidget {
  final String label;
  final Color color;

  const _MiniChip({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }
}
