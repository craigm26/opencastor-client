/// HarnessViewer — read-only visual pipeline of the AgentHarness.
///
/// Shows each layer as a connected card node:
///   P66 Safety → Context Builder → Skills → Dual Model → Trajectory Logger
///
/// Tap any node to expand/collapse details.
/// Pass [onEditLayer] to enable the pencil-icon edit button per node.
/// Tap the ℹ️ icon on any block to see contextual help.
library;

import 'package:flutter/material.dart';

import '../../data/models/harness_config.dart';
import '../../ui/core/theme/app_theme.dart';
import 'flow_canvas.dart';
import 'flow_graph.dart';
import 'harness_design_panels.dart';
import '../shared/loading_view.dart';

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

// ── Block info data ───────────────────────────────────────────────────────────

class _LayerInfoData {
  final String what;
  final String why;
  final String canDo;
  final String interactions;

  const _LayerInfoData({
    required this.what,
    required this.why,
    required this.canDo,
    required this.interactions,
  });
}

/// Info text for each layer type/id. Looked up first by layer.id, then by layer.type.
const _kLayerInfo = <String, _LayerInfoData>{
  'hook-p66': _LayerInfoData(
    what:
        'Protocol 66 Safety Hook — intercepts every command and enforces ESTOP bypass, scope gating, and physical consent (R2RAM). Cannot be disabled.',
    why:
        'Must run first so no command can ever bypass safety checks, regardless of other layers.',
    canDo: 'View audit log in the Trajectory Logger.',
    interactions:
        'Blocks all CommandScope.control commands that lack physical consent.',
  ),
  'prompt-guard': _LayerInfoData(
    what:
        'Prompt injection and jailbreak filter. Scores each incoming message and blocks it if risk exceeds the threshold.',
    why: 'Runs before context assembly so malicious payloads never reach the model.',
    canDo:
        'Adjust risk_threshold (lower = stricter). Enable/disable per harness.',
    interactions:
        'Blocked messages are forwarded to the Dead Letter Queue if present.',
  ),
  'context': _LayerInfoData(
    what:
        'Assembles the agent context: working memory, telemetry, system prompt, and skill definitions.',
    why: 'Runs before skills and model so all downstream layers have full context.',
    canDo:
        'Toggle individual context sources (memory, telemetry, system_prompt, skills_context).',
    interactions: 'Skills and the model depend on this layer\'s output.',
  ),
  'memory': _LayerInfoData(
    what:
        'Per-session scratchpad for multi-step reasoning. Stores intermediate facts and sub-goals.',
    why:
        'Runs after context assembly and before skills so reasoning state is available during skill execution.',
    canDo: 'Set max_entries and TTL. Disable persistence between sessions.',
    interactions:
        'Context Builder reads from this layer. Trajectory Logger archives it.',
  ),
  'skill': _LayerInfoData(
    what:
        'An executable capability the agent can invoke (navigation, vision, web search, etc.).',
    why: 'Skills run after context is assembled and before model inference.',
    canDo: 'Enable/disable, reorder via drag, edit config, or remove.',
    interactions:
        'Circuit Breaker disables a skill after repeated failures. HITL Gate blocks physical skills pending approval.',
  ),
  'model': _LayerInfoData(
    what:
        'LLM routing layer. Routes inferences to a fast local model or a slow cloud model based on confidence.',
    why: 'Runs after skills so model output depends on skill results and context.',
    canDo: 'Change fast/slow provider and model. Adjust confidence threshold.',
    interactions:
        'Cost Gate halts cloud calls if budget is exceeded. Drift Detection flags off-task outputs.',
  ),
  'hitl': _LayerInfoData(
    what:
        'Human-in-the-Loop gate. Pauses execution and waits for operator approval before physical actions proceed.',
    why: 'Sits between skills and post-processing so a human reviews before actuation.',
    canDo:
        'Set timeout, on_timeout policy (block/allow), and action types requiring approval.',
    interactions:
        'Times out to block by default. Works with P66 for double-gating physical commands.',
  ),
  'cost_gate': _LayerInfoData(
    what:
        'Budget ceiling for LLM spend. Halts execution if the session cost exceeds budget_usd.',
    why: 'Runs after model to catch runaway spend before the next iteration.',
    canDo: 'Set budget_usd, on_exceed policy, and alert_at_pct threshold.',
    interactions: 'Works with Dual Model to limit slow (cloud) model invocations.',
  ),
  'circuit_breaker': _LayerInfoData(
    what:
        'Disables a skill after failure_threshold consecutive errors and auto-resets after cooldown_s seconds.',
    why: 'Prevents cascading failures from a broken skill blocking the whole pipeline.',
    canDo: 'Set failure_threshold and cooldown_s. Toggle half-open probe.',
    interactions: 'Resets automatically. Works alongside HITL Gate for physical actions.',
  ),
  'hook': _LayerInfoData(
    what: 'Runtime hook that monitors pipeline execution (e.g. Drift Detection).',
    why: 'Runs after model to inspect outputs without blocking the main flow.',
    canDo: 'Enable/disable. Adjust threshold parameters.',
    interactions:
        'Drift Detection triggers a warning that the Trajectory Logger records.',
  ),
  'guard': _LayerInfoData(
    what: 'Input validation guard. Inspects and blocks unsafe or policy-violating inputs before they reach downstream layers.',
    why: 'Positioned early in the pipeline to reject bad inputs before expensive computation.',
    canDo: 'Adjust block policies and risk threshold.',
    interactions: 'Blocked messages flow to the Dead Letter Queue if configured.',
  ),
  'tracer': _LayerInfoData(
    what:
        'OpenTelemetry-style span tracer. Records every layer execution as a named span in SQLite.',
    why:
        'Runs near the end of the pipeline to capture full execution context including model outputs.',
    canDo: 'Change export format and db_path.',
    interactions:
        'Feeds the same SQLite used by the trajectory logger for unified audit.',
  ),
  'dlq': _LayerInfoData(
    what:
        'Dead Letter Queue. Captures failed commands and blocked messages for human review.',
    why: 'Sits near the end of the pipeline to catch anything that fell through upstream gates.',
    canDo: 'Set db_path and max_size.',
    interactions:
        'Receives blocked messages from Prompt Guard and timed-out HITL gates.',
  ),
  'trajectory': _LayerInfoData(
    what:
        'Always-on audit trail. Every agent run is logged to SQLite — required for RCAN compliance.',
    why: 'Must run last to capture the complete pipeline execution record.',
    canDo: 'Change sqlite_path.',
    interactions:
        'Read by the robot\'s autoresearch system and required for R2RAM consent audits.',
  ),
};

// ── Public widget ─────────────────────────────────────────────────────────────

class HarnessViewer extends StatefulWidget {
  /// The harness config to display.
  final HarnessConfig config;

  /// If provided, a pencil icon appears on each node and calls this when tapped.
  final void Function(HarnessLayer layer)? onEditLayer;

  /// If provided, enables skill toggle switches in [_SkillGroupCard].
  final void Function(HarnessLayer)? onToggleLayer;

  /// If provided, enables drag-to-reorder in [_SkillGroupCard].
  final void Function(int, int)? onReorderSkills;

  /// If provided, shows an "+ Add Skill" button inside [_SkillGroupCard].
  final VoidCallback? onAddSkill;

  /// If provided, shows an "+ Add Block" button below the pipeline.
  final VoidCallback? onAddBlock;

  /// If true, shows a loading shimmer instead of the real pipeline.
  final bool loading;

  const HarnessViewer({
    super.key,
    required this.config,
    this.onEditLayer,
    this.onToggleLayer,
    this.onReorderSkills,
    this.onAddSkill,
    this.onAddBlock,
    this.loading = false,
  });

  @override
  State<HarnessViewer> createState() => _HarnessViewerState();
}

class _HarnessViewerState extends State<HarnessViewer> {
  final _expanded = <String, bool>{};
  bool _showFlow = false;
  late FlowGraph _flowGraph;

  @override
  void initState() {
    super.initState();
    _flowGraph = FlowGraph.autoLayout(
      widget.config.layers.map((l) => l.id).toList(),
    );
  }

  @override
  void didUpdateWidget(HarnessViewer old) {
    super.didUpdateWidget(old);
    if (old.config.layers != widget.config.layers) {
      // Rebuild internal flow graph to match new layer order
      _flowGraph = FlowGraph.autoLayout(
        widget.config.layers.map((l) => l.id).toList(),
      );
    }
  }

  bool _isExpanded(String id) => _expanded[id] ?? false;

  void _toggle(String id) =>
      setState(() => _expanded[id] = !(_expanded[id] ?? false));

  void _showLayerInfo(HarnessLayer layer) {
    final key =
        _kLayerInfo.containsKey(layer.id) ? layer.id : layer.type;
    final info = _kLayerInfo[key];
    if (info == null) return;

    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            Icon(_iconForLayer(layer),
                size: 20,
                color: _borderColorForType(layer.type)),
            const SizedBox(width: 8),
            Expanded(
              child: Text(layer.label,
                  style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _InfoSection(label: 'What it does', text: info.what),
              const SizedBox(height: 12),
              _InfoSection(label: 'Why it\'s here', text: info.why),
              const SizedBox(height: 12),
              _InfoSection(
                  label: 'What you can do', text: info.canDo),
              const SizedBox(height: 12),
              _InfoSection(
                  label: 'Interactions', text: info.interactions),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (widget.loading) {
      return const LoadingView();
    }

    // Flow view removed — list view only (#24)

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

    return Stack(
      children: [
        SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Column(
            children: [
              for (var i = 0; i < pipeline.length; i++) ...[
                _buildPipelineItem(context, pipeline[i]),
                if (i < pipeline.length - 1) _Arrow(),
              ],
              if (widget.onAddBlock != null)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: OutlinedButton.icon(
                    icon: const Icon(Icons.add, size: 14),
                    label: const Text('Add Block'),
                    onPressed: widget.onAddBlock,
                  ),
                ),
              const HarnessDesignPanels(),
            ],
          ),
        ),
        // Flow-view toggle removed per UX review (#24)
      ],
    );
  }

  Widget _buildPipelineItem(BuildContext context, _PipelineItem item) {
    if (item.isSkillGroup) {
      return _SkillGroupCard(
        layers: item.skills!,
        onEditLayer: widget.onEditLayer,
        onToggleSkill: widget.onToggleLayer,
        onReorder: widget.onReorderSkills,
        onAddSkill: widget.onAddSkill,
        onInfo: () => _showLayerInfo(
          // Use the first skill layer as representative for the group info
          item.skills!.isNotEmpty
              ? item.skills!.first
              : const HarnessLayer(
                  id: 'skill-group',
                  type: 'skill',
                  label: 'Skills',
                  description: '',
                  enabled: true,
                ),
        ),
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
      onInfo: () => _showLayerInfo(layer),
      expanded: _isExpanded(layer.id),
      onToggle: () => _toggle(layer.id),
    );
  }
}

// ── Arrow connector ───────────────────────────────────────────────────────────

class _Arrow extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 24,
      child: Center(
        child: Icon(
          Icons.arrow_downward,
          size: 14,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
    );
  }
}

// ── Single layer card ─────────────────────────────────────────────────────────

class _LayerCard extends StatelessWidget {
  final HarnessLayer layer;
  final VoidCallback? onEdit;
  final VoidCallback onInfo;
  final bool expanded;
  final VoidCallback onToggle;

  const _LayerCard({
    required this.layer,
    required this.onEdit,
    required this.onInfo,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = _borderColorForType(layer.type);
    final icon = _iconForLayer(layer);

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header row ──────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                                  fontSize: 14,
                                  fontFamily: 'Space Grotesk'),
                            ),
                            const SizedBox(width: 8),
                            _Badge(
                              layer: layer,
                              showOptional: onEdit != null,
                            ),
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
                  // Info icon
                  IconButton(
                    icon: const Icon(Icons.info_outline, size: 16),
                    tooltip: 'About this block',
                    visualDensity: VisualDensity.compact,
                    onPressed: onInfo,
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
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
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
    );
  }
}

// ── Skills group card ─────────────────────────────────────────────────────────

class _SkillGroupCard extends StatelessWidget {
  final List<HarnessLayer> layers;
  final void Function(HarnessLayer layer)? onEditLayer;
  final void Function(HarnessLayer)? onToggleSkill;
  final void Function(int oldIndex, int newIndex)? onReorder;
  final VoidCallback? onAddSkill;
  final VoidCallback onInfo;
  final bool expanded;
  final VoidCallback onToggle;

  const _SkillGroupCard({
    required this.layers,
    required this.onEditLayer,
    this.onToggleSkill,
    this.onReorder,
    this.onAddSkill,
    required this.onInfo,
    required this.expanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final borderColor = _borderColorForType('skill');
    final activeSkills = layers.where((l) => l.enabled).toList();

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: borderColor, width: 4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──────────────────────────────────────────────────
          InkWell(
            onTap: onToggle,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(16),
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
                              fontSize: 14,
                              fontFamily: 'Space Grotesk'),
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
                    // Info icon
                    IconButton(
                      icon: const Icon(Icons.info_outline, size: 16),
                      tooltip: 'About skills',
                      visualDensity: VisualDensity.compact,
                      onPressed: onInfo,
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
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                child: Column(
                  children: [
                    ReorderableListView(
                      shrinkWrap: true,
                      physics: onReorder != null
                          ? null
                          : const NeverScrollableScrollPhysics(),
                      onReorder: onReorder ?? (_, __) {},
                      children: [
                        for (int si = 0; si < layers.length; si++)
                          _SkillListTile(
                            key: ValueKey(layers[si].id),
                            skill: layers[si],
                            index: si,
                            total: layers.length,
                            onToggle: onToggleSkill != null
                                ? () => onToggleSkill!(layers[si])
                                : null,
                            onEdit: onEditLayer != null
                                ? () => onEditLayer!(layers[si])
                                : null,
                            onMoveUp: (onReorder != null && si > 0)
                                ? () => onReorder!(si, si - 1)
                                : null,
                            onMoveDown:
                                (onReorder != null && si < layers.length - 1)
                                    ? () => onReorder!(si, si + 2)
                                    : null,
                          ),
                      ],
                    ),
                    if (onAddSkill != null)
                      TextButton.icon(
                        icon: const Icon(Icons.add, size: 14),
                        label: const Text('Add Skill'),
                        onPressed: onAddSkill,
                      ),
                  ],
                ),
              ),
          ],
        ),
    );
  }
}

// ── _SkillListTile ────────────────────────────────────────────────────────────

/// A reorderable skill row with:
/// - Order badge (1-based index chip)
/// - Drag handle (long-press to drag)
/// - ↑/↓ quick-move buttons (one step at a time)
/// - Enable switch + edit button
class _SkillListTile extends StatelessWidget {
  final HarnessLayer skill;
  final int index;
  final int total;
  final VoidCallback? onToggle;
  final VoidCallback? onEdit;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;

  const _SkillListTile({
    super.key,
    required this.skill,
    required this.index,
    required this.total,
    this.onToggle,
    this.onEdit,
    this.onMoveUp,
    this.onMoveDown,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final canReorder = skill.canReorder;

    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          // ── Order badge ────────────────────────────────────────────
          SizedBox(
            width: 32,
            child: Center(
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: canReorder
                      ? cs.primary.withValues(alpha: 0.15)
                      : cs.surfaceContainerHighest,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    '${index + 1}',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'Space Grotesk',
                      color: canReorder ? cs.primary : cs.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            ),
          ),

          // ── Drag handle ────────────────────────────────────────────
          if (canReorder)
            ReorderableDragStartListener(
              index: index,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                child: Icon(Icons.drag_handle,
                    size: 18, color: cs.onSurfaceVariant),
              ),
            )
          else
            const SizedBox(width: 26),

          // ── Label + description ────────────────────────────────────
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(skill.label,
                      style: const TextStyle(
                          fontSize: 13, fontWeight: FontWeight.w500)),
                  Text(skill.description,
                      style: TextStyle(
                          fontSize: 11, color: cs.onSurfaceVariant),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                ],
              ),
            ),
          ),

          // ── ↑/↓ quick-move ────────────────────────────────────────
          if (canReorder) ...[
            _ArrowBtn(
              icon: Icons.keyboard_arrow_up_rounded,
              enabled: onMoveUp != null,
              onTap: onMoveUp,
            ),
            _ArrowBtn(
              icon: Icons.keyboard_arrow_down_rounded,
              enabled: onMoveDown != null,
              onTap: onMoveDown,
            ),
          ] else ...[
            const SizedBox(width: 48),
          ],

          // ── Enable switch ──────────────────────────────────────────
          Switch(
            value: skill.enabled,
            onChanged: onToggle != null ? (_) => onToggle!() : null,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),

          // ── Edit button ────────────────────────────────────────────
          if (onEdit != null)
            IconButton(
              icon: const Icon(Icons.edit_outlined, size: 14),
              visualDensity: VisualDensity.compact,
              onPressed: onEdit,
            ),

          const SizedBox(width: 4),
        ],
      ),
    );
  }
}

class _ArrowBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback? onTap;

  const _ArrowBtn({required this.icon, required this.enabled, this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return SizedBox(
      width: 24,
      height: 40,
      child: IconButton(
        icon: Icon(icon, size: 16),
        padding: EdgeInsets.zero,
        visualDensity: VisualDensity.compact,
        color: enabled ? cs.onSurface : cs.onSurfaceVariant.withValues(alpha: 0.3),
        onPressed: enabled ? onTap : null,
      ),
    );
  }
}


// ── Helpers ───────────────────────────────────────────────────────────────────

class _Badge extends StatelessWidget {
  final HarnessLayer layer;

  /// When true, show an OPTIONAL chip for canDisable layers (i.e. edit mode).
  final bool showOptional;

  const _Badge({required this.layer, this.showOptional = false});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (!layer.canDisable) {
      return _chip('always-on', AppTheme.danger);
    }
    if (!layer.enabled) {
      return _chip('off', cs.onSurfaceVariant);
    }
    if (showOptional) {
      return _chip('optional', cs.primary);
    }
    return const SizedBox.shrink();
  }

  Widget _chip(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: color.withValues(alpha: 0.3)),
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

class _InfoSection extends StatelessWidget {
  final String label;
  final String text;

  const _InfoSection({required this.label, required this.text});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600, fontSize: 12)),
        const SizedBox(height: 2),
        Text(text,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
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
