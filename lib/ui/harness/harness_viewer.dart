/// HarnessViewer — read-only visual pipeline of the AgentHarness.
///
/// Shows each layer as a connected card node:
///   P66 Safety → Context Builder → Skills → Dual Model → Trajectory Logger
///
/// Tap any node to expand/collapse details.
/// Pass [onEditLayer] to enable the pencil-icon edit button per node.
library;

import 'package:flutter/material.dart';

import '../../data/models/harness_config.dart';
import '../../ui/core/theme/app_theme.dart';

// ── Layer colour palette ──────────────────────────────────────────────────────

Color _borderColorForType(String type) {
  switch (type) {
    case 'hook':
      return AppTheme.danger; // red for P66, hooks
    case 'context':
      return const Color(0xFF0ea5e9); // sky-blue
    case 'skill':
      return const Color(0xFF22c55e); // green
    case 'model':
      return const Color(0xFFa855f7); // purple
    case 'trajectory':
      return const Color(0xFF94a3b8); // slate/gray
    default:
      return const Color(0xFF64748b);
  }
}

IconData _iconForLayer(HarnessLayer layer) {
  if (layer.id == 'hook-p66') return Icons.security;
  if (layer.id == 'hook-drift') return Icons.track_changes;
  switch (layer.type) {
    case 'hook':
      return Icons.shield_outlined;
    case 'context':
      return Icons.article_outlined;
    case 'skill':
      return Icons.build_outlined;
    case 'model':
      return Icons.psychology_outlined;
    case 'trajectory':
      return Icons.bar_chart_outlined;
    default:
      return Icons.layers_outlined;
  }
}

// ── Public widget ─────────────────────────────────────────────────────────────

class HarnessViewer extends StatefulWidget {
  /// The harness config to display.
  final HarnessConfig config;

  /// If provided, a pencil icon appears on each node and calls this when tapped.
  final void Function(HarnessLayer layer)? onEditLayer;

  /// If true, shows a loading shimmer instead of the real pipeline.
  final bool loading;

  const HarnessViewer({
    super.key,
    required this.config,
    this.onEditLayer,
    this.loading = false,
  });

  @override
  State<HarnessViewer> createState() => _HarnessViewerState();
}

class _HarnessViewerState extends State<HarnessViewer> {
  final _expanded = <String, bool>{};

  bool _isExpanded(String id) => _expanded[id] ?? false;

  void _toggle(String id) =>
      setState(() => _expanded[id] = !(_expanded[id] ?? false));

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const Center(child: CircularProgressIndicator());
    }

    // Build the ordered display groups:
    // [P66] → [Context] → [Skills group] → [Drift hook] → [Model] → [Trajectory]
    final p66 = widget.config.layers
        .where((l) => l.id == 'hook-p66')
        .toList();
    final ctx = widget.config.layers
        .where((l) => l.type == 'context')
        .toList();
    final skills = widget.config.skillLayers;
    final drift = widget.config.layers
        .where((l) => l.id == 'hook-drift')
        .toList();
    final model = widget.config.layers
        .where((l) => l.type == 'model')
        .toList();
    final traj = widget.config.layers
        .where((l) => l.type == 'trajectory')
        .toList();

    // Flatten into pipeline order
    final pipeline = <_PipelineItem>[];
    for (final l in p66) {
      pipeline.add(_PipelineItem.single(l));
    }
    for (final l in ctx) {
      pipeline.add(_PipelineItem.single(l));
    }
    if (skills.isNotEmpty) {
      pipeline.add(_PipelineItem.skillGroup(skills));
    }
    for (final l in drift) {
      pipeline.add(_PipelineItem.single(l));
    }
    for (final l in model) {
      pipeline.add(_PipelineItem.single(l));
    }
    for (final l in traj) {
      pipeline.add(_PipelineItem.single(l));
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(
        children: [
          for (var i = 0; i < pipeline.length; i++) ...[
            _buildPipelineItem(context, pipeline[i]),
            if (i < pipeline.length - 1) _Arrow(),
          ],
        ],
      ),
    );
  }

  Widget _buildPipelineItem(BuildContext context, _PipelineItem item) {
    if (item.isSkillGroup) {
      return _SkillGroupCard(
        layers: item.skills!,
        onEditLayer: widget.onEditLayer,
        expanded: _isExpanded('skills-group'),
        onToggle: () => _toggle('skills-group'),
      );
    }
    final layer = item.layer!;
    return _LayerCard(
      layer: layer,
      onEdit: widget.onEditLayer != null
          ? () => widget.onEditLayer!(layer)
          : null,
      expanded: _isExpanded(layer.id),
      onToggle: () => _toggle(layer.id),
    );
  }
}

// ── Arrow connector ───────────────────────────────────────────────────────────

class _Arrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      height: 24,
      child: Center(
        child: Column(
          children: [
            Container(width: 2, height: 10, color: cs.outlineVariant),
            Icon(Icons.arrow_downward,
                size: 14, color: cs.outlineVariant),
          ],
        ),
      ),
    );
  }
}

// ── Single layer card ─────────────────────────────────────────────────────────

class _LayerCard extends StatelessWidget {
  final HarnessLayer layer;
  final VoidCallback? onEdit;
  final bool expanded;
  final VoidCallback onToggle;

  const _LayerCard({
    required this.layer,
    required this.onEdit,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = _borderColorForType(layer.type);
    final icon = _iconForLayer(layer);

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      color: isDark ? const Color(0xFF12142b) : cs.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: borderColor, width: 4)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header row ──────────────────────────────────────────────
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(icon, size: 18, color: borderColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                layer.label,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 14),
                              ),
                              const SizedBox(width: 8),
                              _Badge(layer: layer),
                            ],
                          ),
                          if (!expanded)
                            Text(
                              layer.description,
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (onEdit != null)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined, size: 16),
                        tooltip: 'Edit layer',
                        visualDensity: VisualDensity.compact,
                        onPressed: onEdit,
                      ),
                    Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // ── Expanded detail panel ────────────────────────────────────
            if (expanded)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(14, 0, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(layer.description,
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant)),
                    if (layer.config.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      _ConfigTable(config: layer.config),
                    ],
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Skills group card ─────────────────────────────────────────────────────────

class _SkillGroupCard extends StatelessWidget {
  final List<HarnessLayer> layers;
  final void Function(HarnessLayer layer)? onEditLayer;
  final bool expanded;
  final VoidCallback onToggle;

  const _SkillGroupCard({
    required this.layers,
    required this.onEditLayer,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final borderColor = _borderColorForType('skill');
    final activeSkills = layers.where((l) => l.enabled).toList();

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: cs.outlineVariant.withOpacity(0.4)),
      ),
      color: isDark ? const Color(0xFF12142b) : cs.surface,
      child: Container(
        decoration: BoxDecoration(
          border: Border(left: BorderSide(color: borderColor, width: 4)),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(12),
            bottomLeft: Radius.circular(12),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────
            InkWell(
              onTap: onToggle,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                child: Row(
                  children: [
                    Icon(Icons.build_outlined,
                        size: 18, color: borderColor),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Skills (${activeSkills.length} active)',
                            style: const TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 14),
                          ),
                          if (!expanded)
                            Text(
                              activeSkills.isEmpty
                                  ? 'No active skills'
                                  : activeSkills
                                      .map((l) => l.label)
                                      .join(' → '),
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    Icon(
                      expanded
                          ? Icons.expand_less
                          : Icons.expand_more,
                      size: 18,
                      color: cs.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),

            // ── Skill list ───────────────────────────────────────────────
            if (expanded)
              Padding(
                padding:
                    const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: layers.map((skill) {
                    return ListTile(
                      dense: true,
                      leading: Icon(
                        skill.enabled
                            ? Icons.check_circle_outline
                            : Icons.radio_button_unchecked,
                        size: 16,
                        color: skill.enabled
                            ? borderColor
                            : cs.onSurfaceVariant,
                      ),
                      title: Text(skill.label,
                          style: const TextStyle(fontSize: 13)),
                      subtitle: Text(skill.description,
                          style:
                              TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
                      trailing: onEditLayer != null
                          ? IconButton(
                              icon: const Icon(Icons.edit_outlined,
                                  size: 14),
                              visualDensity: VisualDensity.compact,
                              onPressed: () => onEditLayer!(skill),
                            )
                          : null,
                      contentPadding:
                          const EdgeInsets.symmetric(horizontal: 4),
                    );
                  }).toList(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final HarnessLayer layer;
  const _Badge({required this.layer});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!layer.canDisable) {
      return _chip('always-on', AppTheme.danger);
    }
    if (!layer.enabled) {
      return _chip('off', cs.onSurfaceVariant);
    }
    return const SizedBox.shrink();
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withOpacity(0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 9, color: color, fontWeight: FontWeight.w600),
        ),
      );
}

class _ConfigTable extends StatelessWidget {
  final Map<String, dynamic> config;
  const _ConfigTable({required this.config});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final entries = config.entries.toList();
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      children: entries.map((e) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('${e.key}: ',
                style: TextStyle(
                    fontSize: 11,
                    color: cs.onSurfaceVariant,
                    fontFamily: 'monospace')),
            Text(
              '${e.value}',
              style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  fontFamily: 'monospace'),
            ),
          ],
        );
      }).toList(),
    );
  }
}

// ── Internal pipeline item model ──────────────────────────────────────────────

class _PipelineItem {
  final HarnessLayer? layer;
  final List<HarnessLayer>? skills;
  bool get isSkillGroup => skills != null;

  const _PipelineItem._({this.layer, this.skills});

  factory _PipelineItem.single(HarnessLayer l) =>
      _PipelineItem._(layer: l);

  factory _PipelineItem.skillGroup(List<HarnessLayer> s) =>
      _PipelineItem._(skills: s);
}
