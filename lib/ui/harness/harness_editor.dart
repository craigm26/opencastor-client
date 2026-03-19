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
import 'package:url_launcher/url_launcher.dart';

import '../../data/models/command.dart' show CommandScope;
import '../../data/models/harness_config.dart';
import '../../data/models/hub_config.dart';
import '../../data/models/provider_models.dart';
import '../../ui/core/theme/app_theme.dart';
import '../explore/explore_view_model.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import 'harness_viewer.dart';
import 'model_garage.dart';

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
    });
  }

  void _addLayer(HarnessLayer layer) {
    setState(() {
      _config = _config.withLayerAdded(layer);
    });
  }

  Future<void> _removeLayer(HarnessLayer layer) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove block?'),
        content: Text(
          'Remove "${layer.label}" from the harness?\n\n'
          'This cannot be undone in the current session.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppTheme.danger,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    setState(() {
      _config = _config.withLayerRemoved(layer.id);
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

  // ── Show Add Block sheet ──────────────────────────────────────────────────

  void _showAddBlockSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => _AddBlockSheet(
        config: _config,
        onAddLayer: (layer) {
          Navigator.pop(ctx);
          _addLayer(layer);
        },
        onOpenSkillBrowser: () {
          Navigator.pop(ctx);
          _showSkillBrowser();
        },
      ),
    );
  }

  void _showSkillBrowser() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SizedBox(
        height: MediaQuery.of(ctx).size.height * 0.9,
        child: SkillBrowserSheet(
          config: _config,
          onAdd: (layer) {
            Navigator.pop(ctx);
            _addLayer(layer);
          },
        ),
      ),
    );
  }

  // ── Open layer edit bottom sheet ──────────────────────────────────────────

  void _openEditSheet(HarnessLayer layer) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.6,
        minChildSize: 0.4,
        maxChildSize: 0.92,
        expand: false,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          child: _LayerEditPanel(
            key: ValueKey(layer.id),
            rrn: widget.rrn,
            layer: layer,
            onToggle: (l) {
              _toggleLayerEnabled(l);
              Navigator.pop(ctx);
            },
            onConfigChanged: _updateLayerConfig,
            onClose: () => Navigator.pop(ctx),
            onRemove: layer.canDisable
                ? () {
                    _removeLayer(layer);
                    Navigator.pop(ctx);
                  }
                : null,
          ),
        ),
      ),
    );
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
      floatingActionButton: FloatingActionButton.small(
        onPressed: _showAddBlockSheet,
        tooltip: 'Add block',
        child: const Icon(Icons.add),
      ),
      body: HarnessViewer(
        config: _config,
        onEditLayer: _openEditSheet,
        onToggleLayer: _toggleLayerEnabled,
        onReorderSkills: _reorderSkills,
        onAddSkill: _showSkillBrowser,
        onAddBlock: _showAddBlockSheet,
      ),
    );
  }
}

// ── Layer edit panel ──────────────────────────────────────────────────────────

class _LayerEditPanel extends StatefulWidget {
  final String rrn;
  final HarnessLayer layer;
  final void Function(HarnessLayer) onToggle;
  final void Function(HarnessLayer, Map<String, dynamic>) onConfigChanged;
  final VoidCallback onClose;
  final VoidCallback? onRemove;

  const _LayerEditPanel({
    super.key,
    required this.rrn,
    required this.layer,
    required this.onToggle,
    required this.onConfigChanged,
    required this.onClose,
    this.onRemove,
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

  @override
  void didUpdateWidget(_LayerEditPanel old) {
    super.didUpdateWidget(old);
    // Refresh local config snapshot when the parent swaps in a new layer
    // (e.g. after a toggle or external config change).
    if (old.layer.id != widget.layer.id ||
        old.layer.config != widget.layer.config) {
      _config = Map<String, dynamic>.from(widget.layer.config);
    }
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
                  message: widget.layer.type == 'trajectory'
                      ? 'Trajectory logging is always on — required for RCAN audit compliance'
                      : 'P66 layer cannot be disabled',
                  child: Chip(
                    avatar: Icon(Icons.lock_outline,
                        size: 12, color: AppTheme.danger),
                    label: const Text('always-on'),
                    backgroundColor: AppTheme.danger.withValues(alpha: 0.12),
                    labelStyle:
                        TextStyle(fontSize: 10, color: AppTheme.danger),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              // Delete button for removable layers
              if (widget.onRemove != null)
                IconButton(
                  icon: Icon(Icons.delete_outline,
                      size: 18, color: AppTheme.danger),
                  tooltip: 'Remove block from harness',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onRemove,
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
          onRemove: widget.onRemove,
        );

      case 'context':
        return _ContextEditor(config: _config, onUpdate: _updateConfig);

      case 'model':
        return _ModelEditor(
          rrn: widget.rrn,
          config: _config,
          onUpdate: _updateConfig,
        );

      case 'trajectory':
        return _TrajectoryEditor(
          config: _config,
          onUpdate: _updateConfig,
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

/// Scope badge colours (same palette as HarnessViewer border colours).
Color _scopeColor(String scope) {
  switch (scope) {
    case 'control':
      return const Color(0xFFf59e0b); // amber
    case 'status':
      return const Color(0xFF0ea5e9); // sky-blue
    case 'chat':
      return const Color(0xFF22c55e); // green
    default:
      return const Color(0xFF94a3b8);
  }
}

/// Builtin skill metadata (matches SkillBrowserSheet._builtinSkills).
const _kBuiltinSkillMeta = <String, Map<String, String>>{
  'navigate-to': {
    'label': 'Navigate-To',
    'description': 'Point-to-point navigation',
    'scope': 'control',
  },
  'camera-describe': {
    'label': 'Camera Describe',
    'description': 'Scene description via OAK-D',
    'scope': 'status',
  },
  'arm-manipulate': {
    'label': 'Arm Manipulate',
    'description': 'SO-ARM101 joint control',
    'scope': 'control',
  },
  'web-lookup': {
    'label': 'Web Lookup',
    'description': 'Live web search & summarization',
    'scope': 'chat',
  },
  'peer-coordinate': {
    'label': 'Peer Coordinate',
    'description': 'Multi-robot task delegation',
    'scope': 'chat',
  },
  'code-reviewer': {
    'label': 'Code Reviewer',
    'description': 'Automated code review',
    'scope': 'chat',
  },
};

class _SkillEditor extends StatelessWidget {
  final HarnessLayer layer;
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;
  final VoidCallback? onRemove;

  const _SkillEditor({
    required this.layer,
    required this.config,
    required this.onUpdate,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final meta = _kBuiltinSkillMeta[layer.label];
    final scope = meta?['scope'] ?? 'chat';
    final description =
        meta?['description'] ?? layer.description;
    final isBuiltin = meta != null;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Scope badge + order
        Row(
          children: [
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: _scopeColor(scope).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                    color: _scopeColor(scope).withValues(alpha: 0.4)),
              ),
              child: Text(
                scope.toUpperCase(),
                style: TextStyle(
                    fontSize: 10,
                    color: _scopeColor(scope),
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.5),
              ),
            ),
            const SizedBox(width: 10),
            Text('Order: ${config['order'] ?? 0}',
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 6),
        // Description
        Text(description,
            style:
                TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        const SizedBox(height: 12),
        // Action row
        Row(
          children: [
            if (!isBuiltin)
              TextButton.icon(
                icon: const Icon(Icons.open_in_new, size: 14),
                label: const Text('View in Hub'),
                style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact),
                onPressed: () async {
                  final uri = Uri.parse(
                      'https://opencastor.com/config/skill-${layer.label}');
                  if (await canLaunchUrl(uri)) {
                    await launchUrl(uri,
                        mode: LaunchMode.externalApplication);
                  }
                },
              ),
            const Spacer(),
            if (onRemove != null)
              OutlinedButton.icon(
                icon: Icon(Icons.delete_outline,
                    size: 14, color: AppTheme.danger),
                label: Text('Remove',
                    style: TextStyle(color: AppTheme.danger)),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(color: AppTheme.danger.withValues(alpha: 0.5)),
                  visualDensity: VisualDensity.compact,
                ),
                onPressed: onRemove,
              ),
          ],
        ),
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

// ── Model editor with cascading provider → model dropdowns ────────────────────

class _ModelEditor extends StatefulWidget {
  final String rrn;
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;

  const _ModelEditor({
    required this.rrn,
    required this.config,
    required this.onUpdate,
  });

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

  late String _fastProvider;
  late String _fastModel;
  late String _slowProvider;
  late String _slowModel;

  // Controllers for ollama custom model entry
  late TextEditingController _fastCustomCtrl;
  late TextEditingController _slowCustomCtrl;

  @override
  void initState() {
    super.initState();
    _fastProvider =
        widget.config['fast_provider'] as String? ?? 'ollama';
    _fastModel =
        widget.config['fast_model'] as String? ?? 'gemma3:1b';
    _slowProvider =
        widget.config['slow_provider'] as String? ?? 'google';
    _slowModel = widget.config['slow_model'] as String? ??
        'gemini-2.0-flash';

    _fastCustomCtrl = TextEditingController(
      text: _isCustomOllama(_fastProvider, _fastModel) ? _fastModel : '',
    );
    _slowCustomCtrl = TextEditingController(
      text: _isCustomOllama(_slowProvider, _slowModel) ? _slowModel : '',
    );
  }

  @override
  void dispose() {
    _fastCustomCtrl.dispose();
    _slowCustomCtrl.dispose();
    super.dispose();
  }

  bool _isCustomOllama(String provider, String model) {
    if (provider != 'ollama') return false;
    final list = kProviderModels['ollama']!;
    return !list.contains(model) || model == kOllamaCustomSentinel;
  }

  List<String> _modelsFor(String provider) =>
      kProviderModels[provider] ?? [];

  /// The dropdown value to display: if it's a custom ollama model,
  /// show the sentinel so the dropdown itself shows 'custom...'.
  String _dropdownValue(String provider, String model) {
    if (provider == 'ollama' &&
        !_modelsFor('ollama').contains(model)) {
      return kOllamaCustomSentinel;
    }
    final models = _modelsFor(provider);
    if (models.contains(model)) return model;
    return models.isNotEmpty ? models.first : model;
  }

  void _onFastProviderChanged(String? v) {
    if (v == null) return;
    final models = _modelsFor(v);
    final newModel =
        models.isNotEmpty ? models.first : '';
    setState(() {
      _fastProvider = v;
      _fastModel = newModel;
      _fastCustomCtrl.text = '';
    });
    widget.onUpdate('fast_provider', v);
    widget.onUpdate('fast_model', newModel);
  }

  void _onFastModelChanged(String? v) {
    if (v == null) return;
    if (v == kOllamaCustomSentinel) {
      setState(() => _fastModel = kOllamaCustomSentinel);
      // Don't propagate sentinel to actual config — wait for custom text
    } else {
      setState(() => _fastModel = v);
      widget.onUpdate('fast_model', v);
    }
  }

  void _onSlowProviderChanged(String? v) {
    if (v == null) return;
    final models = _modelsFor(v);
    final newModel =
        models.isNotEmpty ? models.first : '';
    setState(() {
      _slowProvider = v;
      _slowModel = newModel;
      _slowCustomCtrl.text = '';
    });
    widget.onUpdate('slow_provider', v);
    widget.onUpdate('slow_model', newModel);
  }

  void _onSlowModelChanged(String? v) {
    if (v == null) return;
    if (v == kOllamaCustomSentinel) {
      setState(() => _slowModel = kOllamaCustomSentinel);
    } else {
      setState(() => _slowModel = v);
      widget.onUpdate('slow_model', v);
    }
  }

  @override
  Widget build(BuildContext context) {
    final fastDropVal =
        _dropdownValue(_fastProvider, _fastModel);
    final slowDropVal =
        _dropdownValue(_slowProvider, _slowModel);
    final showFastCustom = fastDropVal == kOllamaCustomSentinel;
    final showSlowCustom = slowDropVal == kOllamaCustomSentinel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Model Garage button ────────────────────────────────────────
        Align(
          alignment: Alignment.centerRight,
          child: OutlinedButton.icon(
            icon: const Text('🔧', style: TextStyle(fontSize: 14)),
            label: const Text('Open Garage',
                style: TextStyle(fontSize: 12)),
            style: OutlinedButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () async {
              final sel = await ModelGarage.open(
                context,
                rrn: widget.rrn,
                currentFastProvider: _fastProvider,
                currentFastModel: _fastModel,
                currentSlowProvider: _slowProvider,
                currentSlowModel: _slowModel,
              );
              if (sel == null) return;
              if (sel.tier == 'fast') {
                setState(() {
                  _fastProvider = sel.provider;
                  _fastModel = sel.model;
                  _fastCustomCtrl.text =
                      _isCustomOllama(sel.provider, sel.model)
                          ? sel.model
                          : '';
                });
                widget.onUpdate('fast_provider', sel.provider);
                widget.onUpdate('fast_model', sel.model);
              } else {
                setState(() {
                  _slowProvider = sel.provider;
                  _slowModel = sel.model;
                  _slowCustomCtrl.text =
                      _isCustomOllama(sel.provider, sel.model)
                          ? sel.model
                          : '';
                });
                widget.onUpdate('slow_provider', sel.provider);
                widget.onUpdate('slow_model', sel.model);
              }
            },
          ),
        ),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Fast tier ──────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Fast provider',
                      style: TextStyle(fontSize: 11)),
                  DropdownButtonFormField<String>(
                    key: ValueKey('fast-provider-$_fastProvider'),
                    initialValue: _fastProvider,
                    isDense: true,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: _providers
                        .map((p) =>
                            DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: _onFastProviderChanged,
                  ),
                  const SizedBox(height: 4),
                  const Text('Fast model',
                      style: TextStyle(fontSize: 11)),
                  DropdownButtonFormField<String>(
                    key: ValueKey('fast-model-$fastDropVal-$_fastProvider'),
                    initialValue: fastDropVal,
                    isDense: true,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: _modelsFor(_fastProvider)
                        .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m,
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _onFastModelChanged,
                  ),
                  if (showFastCustom) ...[
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _fastCustomCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Custom model name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setState(() => _fastModel = v);
                        widget.onUpdate('fast_model', v);
                      },
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            // ── Slow tier ──────────────────────────────────────────────
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Slow provider',
                      style: TextStyle(fontSize: 11)),
                  DropdownButtonFormField<String>(
                    key: ValueKey('slow-provider-$_slowProvider'),
                    initialValue: _slowProvider,
                    isDense: true,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: _providers
                        .map((p) =>
                            DropdownMenuItem(value: p, child: Text(p)))
                        .toList(),
                    onChanged: _onSlowProviderChanged,
                  ),
                  const SizedBox(height: 4),
                  const Text('Slow model',
                      style: TextStyle(fontSize: 11)),
                  DropdownButtonFormField<String>(
                    key: ValueKey('slow-model-$slowDropVal-$_slowProvider'),
                    initialValue: slowDropVal,
                    isDense: true,
                    decoration: const InputDecoration(
                        isDense: true, border: OutlineInputBorder()),
                    items: _modelsFor(_slowProvider)
                        .map((m) => DropdownMenuItem(
                            value: m,
                            child: Text(m,
                                overflow: TextOverflow.ellipsis)))
                        .toList(),
                    onChanged: _onSlowModelChanged,
                  ),
                  if (showSlowCustom) ...[
                    const SizedBox(height: 4),
                    TextFormField(
                      controller: _slowCustomCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Custom model name',
                        isDense: true,
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        setState(() => _slowModel = v);
                        widget.onUpdate('slow_model', v);
                      },
                    ),
                  ],
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
  final Map<String, dynamic> config;
  final void Function(String, dynamic) onUpdate;

  const _TrajectoryEditor({
    required this.config,
    required this.onUpdate,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
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

// ── Add Block bottom sheet ────────────────────────────────────────────────────

class _AddBlockSheet extends StatelessWidget {
  final HarnessConfig config;
  final void Function(HarnessLayer) onAddLayer;
  final VoidCallback onOpenSkillBrowser;

  const _AddBlockSheet({
    required this.config,
    required this.onAddLayer,
    required this.onOpenSkillBrowser,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final blocks = [
      _BlockEntry(
        emoji: '🔧',
        title: 'Skill',
        subtitle: 'Add a builtin or community skill',
        onAdd: onOpenSkillBrowser,
      ),
      _BlockEntry(
        emoji: '🔄',
        title: 'Drift Detector',
        subtitle: 'Detect model off-task drift after 3+ iterations',
        onAdd: () {
          // Avoid duplicates
          if (config.layers.any((l) => l.id == 'hook-drift')) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Drift Detector is already in this harness'),
                  behavior: SnackBarBehavior.floating),
            );
            return;
          }
          onAddLayer(const HarnessLayer(
            id: 'hook-drift',
            type: 'hook',
            label: 'Drift Detection',
            description:
                'Detects model off-task drift after 3+ iterations',
            enabled: true,
            config: {'drift_threshold': 0.15},
          ));
        },
      ),
      _BlockEntry(
        emoji: '🧠',
        title: 'Second Model Tier',
        subtitle: 'Add a second model layer with provider/model config',
        onAdd: () {
          final id =
              'model-secondary-${DateTime.now().millisecondsSinceEpoch}';
          onAddLayer(HarnessLayer(
            id: id,
            type: 'model',
            label: 'Second Model',
            description: 'Additional model tier for specialised tasks',
            enabled: true,
            config: const {
              'fast_provider': 'google',
              'fast_model': 'gemini-2.5-flash',
              'slow_provider': 'anthropic',
              'slow_model': 'claude-sonnet-4-5',
              'confidence_threshold': 0.7,
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '📝',
        title: 'Custom Context',
        subtitle: 'Inject additional context into the agent pipeline',
        onAdd: () {
          final id =
              'context-custom-${DateTime.now().millisecondsSinceEpoch}';
          onAddLayer(HarnessLayer(
            id: id,
            type: 'context',
            label: 'Custom Context',
            description: 'Additional context sources for this pipeline',
            enabled: true,
            config: const {
              'memory': true,
              'telemetry': false,
              'system_prompt': true,
              'skills_context': true,
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '🔗',
        title: 'Peer Coordinator',
        subtitle: 'Multi-robot task delegation via RCAN',
        onAdd: () {
          if (config.layers.any((l) => l.id == 'skill-peer-coordinate')) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content:
                      Text('Peer Coordinator is already in this harness'),
                  behavior: SnackBarBehavior.floating),
            );
            return;
          }
          final order = config.skillLayers.length;
          onAddLayer(HarnessLayer(
            id: 'skill-peer-coordinate',
            type: 'skill',
            label: 'peer-coordinate',
            description: 'Multi-robot coordination via RCAN',
            enabled: true,
            config: {'order': order},
          ));
        },
      ),
    ];

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Handle
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: cs.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Text('Add a harness block',
                style: const TextStyle(
                    fontSize: 16, fontWeight: FontWeight.bold)),
            const SizedBox(height: 12),
            ...blocks.map((b) => _BlockRow(entry: b)),
          ],
        ),
      ),
    );
  }
}

class _BlockEntry {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onAdd;

  const _BlockEntry({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onAdd,
  });
}

class _BlockRow extends StatelessWidget {
  final _BlockEntry entry;

  const _BlockRow({required this.entry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Text(entry.emoji, style: const TextStyle(fontSize: 20)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(entry.title,
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600)),
                Text(entry.subtitle,
                    style: TextStyle(
                        fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
                visualDensity: VisualDensity.compact),
            onPressed: entry.onAdd,
            child: const Text('+ Add',
                style: TextStyle(fontSize: 12)),
          ),
        ],
      ),
    );
  }
}

// ── Skill browser sheet ───────────────────────────────────────────────────────

class SkillBrowserSheet extends ConsumerStatefulWidget {
  final HarnessConfig config;
  final void Function(HarnessLayer skill) onAdd;

  const SkillBrowserSheet({
    super.key,
    required this.config,
    required this.onAdd,
  });

  /// Builtin skills (static list matching castor/skills/builtin/).
  static const _builtinSkills = <Map<String, String>>[
    {
      'id': 'navigate-to',
      'label': 'Navigate-To',
      'description': 'Point-to-point navigation',
      'scope': 'control',
    },
    {
      'id': 'camera-describe',
      'label': 'Camera Describe',
      'description': 'Scene description via OAK-D',
      'scope': 'status',
    },
    {
      'id': 'arm-manipulate',
      'label': 'Arm Manipulate',
      'description': 'SO-ARM101 joint control',
      'scope': 'control',
    },
    {
      'id': 'web-lookup',
      'label': 'Web Lookup',
      'description': 'Live web search & summarization',
      'scope': 'chat',
    },
    {
      'id': 'peer-coordinate',
      'label': 'Peer Coordinate',
      'description': 'Multi-robot task delegation',
      'scope': 'chat',
    },
    {
      'id': 'code-reviewer',
      'label': 'Code Reviewer',
      'description': 'Automated code review',
      'scope': 'chat',
    },
  ];

  @override
  ConsumerState<SkillBrowserSheet> createState() =>
      _SkillBrowserSheetState();
}

class _SkillBrowserSheetState extends ConsumerState<SkillBrowserSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  bool _alreadyInHarness(String skillId) {
    return widget.config.layers.any((l) => l.id == 'skill-$skillId');
  }

  void _addBuiltinSkill(Map<String, String> skill) {
    final id = 'skill-${skill['id']}';
    if (widget.config.layers.any((l) => l.id == id)) return;
    final order = widget.config.skillLayers.length;
    widget.onAdd(HarnessLayer(
      id: id,
      type: 'skill',
      label: skill['id']!,
      description: skill['description']!,
      enabled: true,
      config: {'order': order},
    ));
  }

  void _addCommunitySkill(HubConfig hubSkill) {
    final id = 'skill-community-${hubSkill.id}';
    if (widget.config.layers.any((l) => l.id == id)) return;
    final order = widget.config.skillLayers.length;
    widget.onAdd(HarnessLayer(
      id: id,
      type: 'skill',
      label: hubSkill.title,
      description: hubSkill.description,
      enabled: true,
      config: {
        'order': order,
        'hub_id': hubSkill.id,
        'provider': hubSkill.provider,
      },
    ));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return Column(
      children: [
        // Handle
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: cs.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),
        // Title + close
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              const Text('Skill Browser',
                  style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.bold)),
              const Spacer(),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
        ),
        // Search field
        Padding(
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search skills…',
              prefixIcon: const Icon(Icons.search, size: 20),
              isDense: true,
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            ),
            onChanged: (v) => setState(() => _search = v.toLowerCase()),
          ),
        ),
        // Tabs
        TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Builtin'),
            Tab(text: 'Community'),
          ],
        ),
        // Tab content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _BuiltinSkillTab(
                search: _search,
                alreadyInHarness: _alreadyInHarness,
                onAdd: _addBuiltinSkill,
              ),
              _CommunitySkillTab(
                search: _search,
                config: widget.config,
                onAdd: _addCommunitySkill,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _BuiltinSkillTab extends StatelessWidget {
  final String search;
  final bool Function(String id) alreadyInHarness;
  final void Function(Map<String, String> skill) onAdd;

  const _BuiltinSkillTab({
    required this.search,
    required this.alreadyInHarness,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context) {
    final skills = SkillBrowserSheet._builtinSkills.where((s) {
      if (search.isEmpty) return true;
      return (s['label'] ?? '').toLowerCase().contains(search) ||
          (s['description'] ?? '').toLowerCase().contains(search);
    }).toList();

    if (skills.isEmpty) {
      return const Center(
          child: Text('No matching skills', style: TextStyle(fontSize: 13)));
    }

    return ListView.builder(
      padding: const EdgeInsets.all(12),
      itemCount: skills.length,
      itemBuilder: (ctx, i) {
        final skill = skills[i];
        final added = alreadyInHarness(skill['id']!);
        return _SkillCard(
          id: skill['id']!,
          label: skill['label']!,
          description: skill['description']!,
          scope: skill['scope']!,
          isAdded: added,
          onAdd: added ? null : () => onAdd(skill),
        );
      },
    );
  }
}

class _CommunitySkillTab extends ConsumerWidget {
  final String search;
  final HarnessConfig config;
  final void Function(HubConfig skill) onAdd;

  const _CommunitySkillTab({
    required this.search,
    required this.config,
    required this.onAdd,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncSkills =
        ref.watch(exploreConfigsProvider(ExploreFilter.skill));

    return asyncSkills.when(
      loading: () =>
          const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.cloud_off_outlined, size: 36),
              const SizedBox(height: 8),
              Text('Could not load community skills',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              const SizedBox(height: 4),
              Text('$e',
                  style: const TextStyle(fontSize: 11),
                  textAlign: TextAlign.center),
            ],
          ),
        ),
      ),
      data: (skills) {
        final filtered = skills.where((s) {
          if (search.isEmpty) return true;
          return s.title.toLowerCase().contains(search) ||
              s.description.toLowerCase().contains(search);
        }).toList();

        if (filtered.isEmpty) {
          return const Center(
              child: Text('No community skills found',
                  style: TextStyle(fontSize: 13)));
        }

        return ListView.builder(
          padding: const EdgeInsets.all(12),
          itemCount: filtered.length,
          itemBuilder: (ctx, i) {
            final skill = filtered[i];
            final added = config.layers
                .any((l) => l.id == 'skill-community-${skill.id}');
            return _SkillCard(
              id: skill.id,
              label: skill.title,
              description: skill.description,
              scope: skill.tags.contains('control')
                  ? 'control'
                  : skill.tags.contains('status')
                      ? 'status'
                      : 'chat',
              isAdded: added,
              onAdd: added ? null : () => onAdd(skill),
              authorName: skill.authorName,
              stars: skill.stars,
            );
          },
        );
      },
    );
  }
}

class _SkillCard extends StatelessWidget {
  final String id;
  final String label;
  final String description;
  final String scope;
  final bool isAdded;
  final VoidCallback? onAdd;
  final String? authorName;
  final int? stars;

  const _SkillCard({
    required this.id,
    required this.label,
    required this.description,
    required this.scope,
    required this.isAdded,
    this.onAdd,
    this.authorName,
    this.stars,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final scopeColor = _scopeColor(scope);

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(label,
                          style: const TextStyle(
                              fontWeight: FontWeight.w600, fontSize: 14)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: scopeColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(
                              color: scopeColor.withValues(alpha: 0.4)),
                        ),
                        child: Text(
                          scope.toUpperCase(),
                          style: TextStyle(
                              fontSize: 9,
                              color: scopeColor,
                              fontWeight: FontWeight.w700),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(description,
                      style: TextStyle(
                          fontSize: 12, color: cs.onSurfaceVariant),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis),
                  if (authorName != null || stars != null) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        if (authorName != null)
                          Text('by $authorName',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant)),
                        if (stars != null) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.star_outline,
                              size: 12,
                              color: cs.onSurfaceVariant),
                          const SizedBox(width: 2),
                          Text('$stars',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: cs.onSurfaceVariant)),
                        ],
                      ],
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 8),
            isAdded
                ? const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: Icon(Icons.check_circle,
                        size: 20, color: Color(0xFF22c55e)),
                  )
                : FilledButton.tonal(
                    style: FilledButton.styleFrom(
                        visualDensity: VisualDensity.compact),
                    onPressed: onAdd,
                    child: const Text('Add',
                        style: TextStyle(fontSize: 12)),
                  ),
          ],
        ),
      ),
    );
  }
}
