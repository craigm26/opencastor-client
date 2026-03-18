/// HarnessEditor — full-screen editor for the AgentHarness pipeline.
///
/// Top section: visual pipeline (interactive HarnessViewer).
/// Bottom section: editing panel for the selected layer.
///
/// Drag-to-reorder skills via ReorderableListView (Flutter stdlib).
/// Save as template → uploadConfig Cloud Function.
/// Deploy to robot → sendCommand(scope: system, instruction: RELOAD_CONFIG).
library;

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/command.dart' show CommandScope;
import '../../data/models/harness_config.dart';
import '../../ui/core/theme/app_theme.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import 'harness_viewer.dart';

// ── Screen ────────────────────────────────────────────────────────────────────

class HarnessEditorScreen extends ConsumerStatefulWidget {
  final String rrn;
  final String robotName;
  final HarnessConfig initialConfig;

  const HarnessEditorScreen({
    super.key,
    required this.rrn,
    required this.robotName,
    required this.initialConfig,
  });

  @override
  ConsumerState<HarnessEditorScreen> createState() =>
      _HarnessEditorScreenState();
}

class _HarnessEditorScreenState extends ConsumerState<HarnessEditorScreen> {
  late HarnessConfig _config;
  HarnessLayer? _selectedLayer;
  bool _saving = false;
  bool _deploying = false;

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
  }

  // ── Layer update helpers ─────────────────────────────────────────────────

  void _toggleLayerEnabled(HarnessLayer layer) {
    if (!layer.canDisable) return;
    setState(() {
      _config = _config.copyWithLayers(
        _config.layers
            .map((l) =>
                l.id == layer.id ? l.copyWith(enabled: !l.enabled) : l)
            .toList(),
      );
      _selectedLayer = _config.layers.firstWhere((l) => l.id == layer.id);
    });
  }

  void _updateLayerConfig(HarnessLayer layer, Map<String, dynamic> newConfig) {
    setState(() {
      _config = _config.copyWithLayers(
        _config.layers
            .map((l) =>
                l.id == layer.id ? l.copyWith(config: newConfig) : l)
            .toList(),
      );
      _selectedLayer = _config.layers.firstWhere((l) => l.id == layer.id);
    });
  }

  void _reorderSkills(int oldIndex, int newIndex) {
    if (newIndex > oldIndex) newIndex -= 1;
    final skills = _config.skillLayers.toList();
    final item = skills.removeAt(oldIndex);
    skills.insert(newIndex, item);

    // Rebuild the full layers list preserving non-skill layer order
    final newLayers = <HarnessLayer>[];
    var skillIdx = 0;
    for (final l in _config.layers) {
      if (l.type == 'skill') {
        newLayers.add(skills[skillIdx++].copyWith(
            config: {...skills[skillIdx - 1].config, 'order': skillIdx - 1}));
      } else {
        newLayers.add(l);
      }
    }
    setState(() {
      _config = _config.copyWithLayers(newLayers);
    });
  }

  // ── Save as template ──────────────────────────────────────────────────────

  Future<void> _saveAsTemplate() async {
    setState(() => _saving = true);
    try {
      final callable =
          FirebaseFunctions.instance.httpsCallable('uploadConfig');
      await callable.call<dynamic>({
        'type': 'harness',
        'title': '${widget.robotName} Harness',
        'tags': [widget.rrn.toLowerCase(), 'harness'],
        'content': _configToYamlString(),
        'filename':
            '${widget.rrn.toLowerCase().replaceAll('-', '_')}.harness.yaml',
        'robot_rrn': widget.rrn,
        'public': false,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Harness saved as template'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Save failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ── Deploy to robot ───────────────────────────────────────────────────────

  Future<void> _deployToRobot() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Deploy Harness Config?'),
        content: Text(
          'Deploy updated harness config to ${widget.robotName}?\n\n'
          'The robot will reload its agent harness. '
          'Existing ESTOP state is preserved.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Deploy'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _deploying = true);
    try {
      // Step 1: Upload config
      final callable =
          FirebaseFunctions.instance.httpsCallable('uploadConfig');
      await callable.call<dynamic>({
        'type': 'harness',
        'title': '${widget.robotName} Harness',
        'tags': [widget.rrn.toLowerCase(), 'harness', 'deployed'],
        'content': _configToYamlString(),
        'filename':
            '${widget.rrn.toLowerCase().replaceAll('-', '_')}.harness.yaml',
        'robot_rrn': widget.rrn,
        'public': false,
      });

      // Step 2: Send RELOAD_CONFIG command
      final repo = ref.read(robotRepositoryProvider);
      await repo.sendCommand(
        rrn: widget.rrn,
        instruction: 'RELOAD_CONFIG',
        scope: CommandScope.system,
        reason: 'Harness config update from OpenCastor app',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Harness deployed to ${widget.robotName}'),
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Deploy failed: $e'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _deploying = false);
    }
  }

  String _configToYamlString() {
    // Simple YAML serialisation from the toYaml() map
    final map = _config.toYaml();
    return _mapToYaml(map, indent: 0);
  }

  String _mapToYaml(dynamic value, {required int indent}) {
    final pad = '  ' * indent;
    if (value is Map) {
      final sb = StringBuffer();
      value.forEach((k, v) {
        if (v is Map || v is List) {
          sb.writeln('$pad$k:');
          sb.write(_mapToYaml(v, indent: indent + 1));
        } else {
          sb.writeln('$pad$k: $v');
        }
      });
      return sb.toString();
    }
    if (value is List) {
      final sb = StringBuffer();
      for (final item in value) {
        sb.writeln('$pad- $item');
      }
      return sb.toString();
    }
    return '$pad$value\n';
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Edit Harness — ${widget.robotName}'),
        actions: [
          if (_saving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            TextButton.icon(
              icon: const Icon(Icons.save_outlined, size: 16),
              label: const Text('Template'),
              onPressed: _saveAsTemplate,
            ),
          const SizedBox(width: 4),
          if (_deploying)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2)),
            )
          else
            FilledButton.icon(
              icon: const Icon(Icons.rocket_launch_outlined, size: 16),
              label: const Text('Deploy'),
              onPressed: _deployToRobot,
            ),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          // ── Top: interactive viewer ──────────────────────────────────────
          Expanded(
            flex: 5,
            child: HarnessViewer(
              config: _config,
              onEditLayer: (layer) =>
                  setState(() => _selectedLayer = layer),
            ),
          ),

          // ── Divider ──────────────────────────────────────────────────────
          const Divider(height: 1),

          // ── Bottom: editing panel ────────────────────────────────────────
          Expanded(
            flex: 4,
            child: _selectedLayer == null
                ? _NoSelectionPanel(skillLayers: _config.skillLayers,
                    onReorder: _reorderSkills)
                : _LayerEditPanel(
                    key: ValueKey(_selectedLayer!.id),
                    layer: _selectedLayer!,
                    onToggle: _toggleLayerEnabled,
                    onConfigChanged: _updateLayerConfig,
                    onClose: () => setState(() => _selectedLayer = null),
                  ),
          ),
        ],
      ),
    );
  }
}

// ── No-selection panel (shows skill reorder list) ─────────────────────────────

class _NoSelectionPanel extends StatelessWidget {
  final List<HarnessLayer> skillLayers;
  final void Function(int oldIndex, int newIndex) onReorder;

  const _NoSelectionPanel({
    required this.skillLayers,
    required this.onReorder,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            'Tap a node to edit · Drag to reorder skills',
            style: TextStyle(
                fontSize: 12, color: cs.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ReorderableListView(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            onReorder: onReorder,
            children: [
              for (final skill in skillLayers)
                ListTile(
                  key: ValueKey(skill.id),
                  dense: true,
                  leading: ReorderableDragStartListener(
                    index: skillLayers.indexOf(skill),
                    child: const Icon(Icons.drag_handle, size: 18),
                  ),
                  title: Text(skill.label,
                      style: const TextStyle(fontSize: 13)),
                  trailing: Switch(
                    value: skill.enabled,
                    onChanged: (_) {},
                    materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Layer edit panel ──────────────────────────────────────────────────────────

class _LayerEditPanel extends StatefulWidget {
  final HarnessLayer layer;
  final void Function(HarnessLayer) onToggle;
  final void Function(HarnessLayer, Map<String, dynamic>) onConfigChanged;
  final VoidCallback onClose;

  const _LayerEditPanel({
    super.key,
    required this.layer,
    required this.onToggle,
    required this.onConfigChanged,
    required this.onClose,
  });

  @override
  State<_LayerEditPanel> createState() => _LayerEditPanelState();
}

class _LayerEditPanelState extends State<_LayerEditPanel> {
  late Map<String, dynamic> _config;

  @override
  void initState() {
    super.initState();
    _config = Map<String, dynamic>.from(widget.layer.config);
  }

  void _updateConfig(String key, dynamic value) {
    setState(() => _config[key] = value);
    widget.onConfigChanged(widget.layer, Map<String, dynamic>.from(_config));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Panel header ───────────────────────────────────────────────
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.layer.label,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              if (widget.layer.canDisable)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Enabled',
                        style: TextStyle(
                            fontSize: 12, color: cs.onSurfaceVariant)),
                    Switch(
                      value: widget.layer.enabled,
                      onChanged: (_) => widget.onToggle(widget.layer),
                      materialTapTargetSize:
                          MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                )
              else
                Tooltip(
                  message: 'P66 layer cannot be disabled',
                  child: Chip(
                    label: const Text('always-on'),
                    backgroundColor: AppTheme.danger.withOpacity(0.12),
                    labelStyle:
                        TextStyle(fontSize: 10, color: AppTheme.danger),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              IconButton(
                icon: const Icon(Icons.close, size: 18),
                onPressed: widget.onClose,
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Type-specific editor ───────────────────────────────────────
          _buildTypeEditor(context),
        ],
      ),
    );
  }

  Widget _buildTypeEditor(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    switch (widget.layer.type) {
      case 'skill':
        return _SkillEditor(
          layer: widget.layer,
          config: _config,
          onUpdate: _updateConfig,
          onToggle: () => widget.onToggle(widget.layer),
        );

      case 'context':
        return _ContextEditor(config: _config, onUpdate: _updateConfig);

      case 'model':
        return _ModelEditor(config: _config, onUpdate: _updateConfig);

      case 'trajectory':
        return _TrajectoryEditor(
          layer: widget.layer,
          config: _config,
          onUpdate: _updateConfig,
          onToggle: () => widget.onToggle(widget.layer),
        );

      case 'hook':
        if (widget.layer.id == 'hook-drift') {
          return _DriftEditor(config: _config, onUpdate: _updateConfig);
        }
        return Text(
          'P66 hook is always-on and cannot be configured here.',
          style: TextStyle(
              fontSize: 12, color: cs.onSurfaceVariant),
        );

      default:
        return const SizedBox.shrink();
    }
  }
}

// ── Sub-editors ────────────────────────────────────────────────────────────────

class _SkillEditor extends StatelessWidget {
  final HarnessLayer layer;
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;
  final VoidCallback onToggle;

  const _SkillEditor({
    required this.layer,
    required this.config,
    required this.onUpdate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Order: ${config['order'] ?? 0}',
                style:
                    TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const Spacer(),
            Text('Enabled', style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Switch(
              value: layer.enabled,
              onChanged: (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        Text(layer.description,
            style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
      ],
    );
  }
}

class _ContextEditor extends StatelessWidget {
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;

  const _ContextEditor({required this.config, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final sources = ['memory', 'telemetry', 'system_prompt', 'skills_context'];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Context sources:', style: TextStyle(fontSize: 12)),
        const SizedBox(height: 4),
        ...sources.map((s) => CheckboxListTile(
              dense: true,
              title: Text(s, style: const TextStyle(fontSize: 13)),
              value: config[s] as bool? ?? true,
              onChanged: (v) => onUpdate(s, v ?? false),
              contentPadding: EdgeInsets.zero,
            )),
      ],
    );
  }
}

class _ModelEditor extends StatefulWidget {
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;

  const _ModelEditor({required this.config, required this.onUpdate});

  @override
  State<_ModelEditor> createState() => _ModelEditorState();
}

class _ModelEditorState extends State<_ModelEditor> {
  static const _providers = [
    'ollama',
    'google',
    'anthropic',
    'openai',
    'groq',
    'mistral',
  ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fast provider',
                      style: TextStyle(fontSize: 11)),
                  DropdownButtonFormField<String>(
                    value: widget.config['fast_provider'] as String? ??
                        'ollama',
                    isDense: true,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: _providers
                        .map((p) =>
                            DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) =>
                        widget.onUpdate('fast_provider', v),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue:
                        widget.config['fast_model'] as String? ??
                            'gemma3:1b',
                    decoration: const InputDecoration(
                      labelText: 'Fast model',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => widget.onUpdate('fast_model', v),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Slow provider',
                      style: TextStyle(fontSize: 11)),
                  DropdownButtonFormField<String>(
                    value: widget.config['slow_provider'] as String? ??
                        'google',
                    isDense: true,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: _providers
                        .map((p) =>
                            DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: (v) =>
                        widget.onUpdate('slow_provider', v),
                  ),
                  const SizedBox(height: 4),
                  TextFormField(
                    initialValue:
                        widget.config['slow_model'] as String? ??
                            'gemini-2.0-flash',
                    decoration: const InputDecoration(
                      labelText: 'Slow model',
                      isDense: true,
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) => widget.onUpdate('slow_model', v),
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          'Confidence threshold: ${(widget.config['confidence_threshold'] as num?)?.toStringAsFixed(2) ?? "0.70"}',
          style: const TextStyle(fontSize: 12),
        ),
        Slider(
          value: (widget.config['confidence_threshold'] as num?)
                  ?.toDouble() ??
              0.7,
          min: 0.0,
          max: 1.0,
          divisions: 20,
          label: (widget.config['confidence_threshold'] as num?)
              ?.toStringAsFixed(2),
          onChanged: (v) =>
              widget.onUpdate('confidence_threshold', v),
        ),
      ],
    );
  }
}

class _TrajectoryEditor extends StatelessWidget {
  final HarnessLayer layer;
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;
  final VoidCallback onToggle;

  const _TrajectoryEditor({
    required this.layer,
    required this.config,
    required this.onUpdate,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text('Enabled',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            Switch(
              value: layer.enabled,
              onChanged: (_) => onToggle(),
              materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
          ],
        ),
        TextFormField(
          initialValue:
              config['sqlite_path'] as String? ?? 'trajectory.db',
          decoration: const InputDecoration(
            labelText: 'SQLite path',
            isDense: true,
            border: OutlineInputBorder(),
          ),
          onChanged: (v) => onUpdate('sqlite_path', v),
        ),
      ],
    );
  }
}

class _DriftEditor extends StatelessWidget {
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;

  const _DriftEditor({required this.config, required this.onUpdate});

  @override
  Widget build(BuildContext context) {
    final threshold =
        (config['drift_threshold'] as num?)?.toDouble() ?? 0.15;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Drift threshold: ${threshold.toStringAsFixed(2)}',
            style: const TextStyle(fontSize: 12)),
        Slider(
          value: threshold,
          min: 0.05,
          max: 0.5,
          divisions: 18,
          label: threshold.toStringAsFixed(2),
          onChanged: (v) => onUpdate('drift_threshold', v),
        ),
        Text(
          'Below this cosine similarity score, the model is flagged as off-task.',
          style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}
