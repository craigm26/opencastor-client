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
import 'config_library_view.dart';

import '../../data/models/command.dart' show CommandScope;
import '../../data/models/harness_config.dart';
import '../../data/models/hub_config.dart';
import '../../data/models/provider_models.dart';
import '../../ui/core/theme/app_theme.dart';
import '../explore/explore_view_model.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import 'flow_canvas.dart';
import 'flow_graph.dart';
import 'harness_validator.dart';
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
  // The deployed baseline — used to compute diffs and enable restore
  late HarnessConfig _deployedConfig;
  bool _saving = false;
  bool _deploying = false;
  bool _showFlow = false;
  // Experiment Mode: changes are sandboxed; no auto-deploy prompt suppressed
  bool _experimentMode = false;
  FlowGraph _flowGraph = FlowGraph.empty();

  @override
  void initState() {
    super.initState();
    _config = widget.initialConfig;
    _deployedConfig = widget.initialConfig;
    _syncGraph();
  }

  /// True when current config differs from the deployed baseline.
  bool get _hasUndeployedChanges =>
      _config.layers.length != _deployedConfig.layers.length ||
      _config.layers.asMap().entries.any((e) {
        final dep = _deployedConfig.layers.length > e.key
            ? _deployedConfig.layers[e.key]
            : null;
        if (dep == null) return true;
        return e.value.id != dep.id ||
            e.value.enabled != dep.enabled ||
            e.value.config.toString() != dep.config.toString();
      });

  /// Compute a human-readable diff summary for the diff bar.
  List<String> get _changeSummary {
    final changes = <String>[];
    final curr = {for (final l in _config.layers) l.id: l};
    final dep = {for (final l in _deployedConfig.layers) l.id: l};

    // Added layers
    for (final id in curr.keys) {
      if (!dep.containsKey(id)) changes.add('+ ${curr[id]!.label}');
    }
    // Removed layers
    for (final id in dep.keys) {
      if (!curr.containsKey(id)) changes.add('− ${dep[id]!.label}');
    }
    // Modified layers (config or enabled changed)
    for (final id in curr.keys) {
      if (!dep.containsKey(id)) continue;
      final c = curr[id]!;
      final d = dep[id]!;
      if (c.enabled != d.enabled) {
        changes.add('${c.enabled ? '✓' : '✗'} ${c.label}');
      } else if (c.config.toString() != d.config.toString()) {
        changes.add('~ ${c.label}');
      }
    }
    return changes;
  }

  /// Apply a single config dimension from a research finding.
  void _applyFinding(String configDim, dynamic value) {
    // Find layers whose config map contains this dimension key
    final updated = _config.layers.map((layer) {
      if (layer.config.containsKey(configDim)) {
        final newConfig = Map<String, dynamic>.from(layer.config)
          ..[configDim] = value;
        return layer.copyWith(config: newConfig);
      }
      return layer;
    }).toList();

    setState(() {
      _config = _config.copyWithLayers(updated);
      _syncGraph();
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Applied: $configDim = $value'),
        backgroundColor: const Color(0xFF1a2527),
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Undo',
          textColor: const Color(0xFFffba38),
          onPressed: () => setState(() {
            _config = _deployedConfig;
            _syncGraph();
          }),
        ),
      ),
    );
  }

  /// Restore to the last deployed config.
  void _restoreToDeployed() {
    setState(() {
      _config = _deployedConfig;
      _syncGraph();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Restored to deployed config'),
        backgroundColor: Color(0xFF1a2527),
      ),
    );
  }

  /// Rebuild the flow graph from the current config layers.
  ///
  /// Preserves existing node positions for layers already in the graph
  /// and auto-lays out any new nodes. Edges are always regenerated to
  /// match the current layer list.
  ///
  /// Keep in sync with: ~/OpenCastor/castor/harness/default_harness.yaml
  void _syncGraph() {
    final layerIds = _config.layers.map((l) => l.id).toList();
    final fresh = FlowGraph.autoLayout(layerIds);
    final existingPosMap = _flowGraph.posMap;
    final mergedPositions = fresh.positions.map((pos) {
      final existing = existingPosMap[pos.layerId];
      if (existing != null) {
        return FlowNodePos(
          layerId: pos.layerId,
          x: existing.x,
          y: existing.y,
          type: pos.type,
          label: pos.label,
          nodeConfig: pos.nodeConfig,
        );
      }
      return pos;
    }).toList();
    _flowGraph = FlowGraph(
      positions: mergedPositions,
      edges: fresh.edges,
      groups: _flowGraph.groups,
    );
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
      _syncGraph();
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
      _syncGraph();
    });
  }

  void _addLayer(HarnessLayer layer) {
    setState(() {
      _config = _config.withLayerAdded(layer);
      _syncGraph();
    });

    // Show placement toast
    final newIdx = _config.layers.indexWhere((l) => l.id == layer.id);
    final prevLabel =
        newIdx > 0 ? _config.layers[newIdx - 1].label : '__input__';

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Added ${layer.label} after $prevLabel'),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 3),
          action: SnackBarAction(
            label: 'View in graph',
            onPressed: () => setState(() => _showFlow = true),
          ),
        ),
      );
    }
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
      _syncGraph();
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
      _syncGraph();
    });
  }

  // ── Insert-on-edge ───────────────────────────────────────────────────────

  /// Called when user taps ⊕ on a flow-canvas edge.
  /// Opens the skill browser; on selection the new layer is inserted between
  /// the edge's fromId and toId nodes (edge is split).
  void _insertOnEdge(FlowEdge edge) {
    _showSkillBrowser(onAdded: (newLayer) {
      // Find the new node's position in the graph
      final newPos = _flowGraph.posMap[newLayer.id];
      if (newPos == null) return;

      // Split the original edge: fromId→newLayer + newLayer→toId
      setState(() {
        _flowGraph.edges.removeWhere(
          (e) => e.fromId == edge.fromId && e.toId == edge.toId,
        );
        _flowGraph.edges.add(FlowEdge(
          id: '${edge.fromId}-${newLayer.id}',
          fromId: edge.fromId,
          toId: newLayer.id,
          label: edge.label,
        ));
        _flowGraph.edges.add(FlowEdge(
          id: '${newLayer.id}-${edge.toId}',
          fromId: newLayer.id,
          toId: edge.toId,
          label: '',
        ));
      });
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
          // Each _BlockEntry already pops the sheet before calling this,
          // so do NOT pop again here — double-pop navigates away from
          // the editor screen entirely.
          _addLayer(layer);
        },
        onOpenSkillBrowser: () {
          Navigator.pop(ctx);
          _showSkillBrowser();
        },
      ),
    );
  }

  void _showSkillBrowser({void Function(HarnessLayer)? onAdded}) {
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
            onAdded?.call(layer);
          },
        ),
      ),
    );
  }

  // ── Open layer edit bottom sheet ──────────────────────────────────────────

  void _openEditSheet(HarnessLayer layer) {
    // Compute position among reorderable (skill) layers for the order badge.
    final skillLayers = _config.skillLayers.toList();
    final layerIndex = skillLayers.indexWhere((l) => l.id == layer.id);

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
            layerIndex: layerIndex >= 0 ? layerIndex : null,
            totalLayers: skillLayers.length,
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
            onMoveUp: (layer.canReorder && layerIndex > 0)
                ? () {
                    _reorderSkills(layerIndex, layerIndex - 1);
                    Navigator.pop(ctx);
                  }
                : null,
            onMoveDown:
                (layer.canReorder && layerIndex < skillLayers.length - 1)
                    ? () {
                        _reorderSkills(layerIndex, layerIndex + 2);
                        Navigator.pop(ctx);
                      }
                    : null,
          ),
        ),
      ),
    );
  }

  // ── Validation dialog ─────────────────────────────────────────────────────

  Future<bool> _showValidationDialog(
    HarnessValidationResult result, {
    required bool blocked,
  }) async {
    return await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: Row(children: [
              Icon(
                blocked ? Icons.block : Icons.warning_amber_rounded,
                color: blocked ? Colors.red : Colors.orange,
              ),
              const SizedBox(width: 8),
              Text(blocked ? 'Harness blocked' : 'Safety warnings'),
            ]),
            content: SizedBox(
              width: 400,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (blocked)
                      const Text(
                        'This harness cannot be saved. Fix the following issues:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    if (!blocked)
                      const Text(
                        'Review these warnings before saving:',
                        style: TextStyle(fontWeight: FontWeight.w500),
                      ),
                    const SizedBox(height: 12),
                    ...result.issues.map((issue) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                issue.severity == ValidationSeverity.block
                                    ? Icons.error_outline
                                    : Icons.warning_amber_outlined,
                                size: 16,
                                color:
                                    issue.severity == ValidationSeverity.block
                                        ? Colors.red
                                        : Colors.orange,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(issue.message,
                                        style:
                                            const TextStyle(fontSize: 13)),
                                    if (issue.fix != null)
                                      Text(
                                        'Fix: ${issue.fix}',
                                        style: TextStyle(
                                          fontSize: 11,
                                          color: Colors.grey.shade600,
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        )),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel'),
              ),
              if (!blocked)
                FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Save anyway'),
                ),
            ],
          ),
        ) ??
        false;
  }

  // ── Save as template ──────────────────────────────────────────────────────

  Future<void> _saveAsTemplate() async {
    // 1. Client-side safety validation
    final validationResult =
        HarnessValidator.validate(_config.layers, _flowGraph);
    if (validationResult.isBlocked) {
      await _showValidationDialog(validationResult, blocked: true);
      return;
    }
    if (validationResult.hasWarnings) {
      final proceed =
          await _showValidationDialog(validationResult, blocked: false);
      if (!proceed) return;
    }

    setState(() => _saving = true);
    try {
      // 2. Use validateAndSaveHarness CF — server-side gate included
      final callable =
          FirebaseFunctions.instance.httpsCallable('validateAndSaveHarness');
      await callable.call<dynamic>({
        'layers': _config.layers.map((l) => l.toJson()).toList(),
        'edges': _flowGraph.edges.map((e) => e.toJson()).toList(),
        'content': _configToYamlString(),
        'title': '${widget.robotName} Harness',
        'tags': [widget.rrn.toLowerCase(), 'harness'],
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

    // Safety validation before deploy
    final validationResult =
        HarnessValidator.validate(_config.layers, _flowGraph);
    if (validationResult.isBlocked) {
      await _showValidationDialog(validationResult, blocked: true);
      return;
    }
    if (validationResult.hasWarnings) {
      final proceed =
          await _showValidationDialog(validationResult, blocked: false);
      if (!proceed) return;
    }

    setState(() => _deploying = true);
    try {
      // Step 1: Upload config (deploy path keeps uploadConfig for robot_rrn tracking)
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
        // Update deployed baseline so diff bar resets
        setState(() => _deployedConfig = _config);
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
        backgroundColor: _experimentMode
            ? const Color(0xFF1a1400)
            : null,
        title: Row(
          children: [
            Text(
              'Edit Harness — ${widget.robotName}',
              style: const TextStyle(fontFamily: 'Space Grotesk'),
            ),
            if (_experimentMode) ...[
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFffba38).withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: const Color(0xFFffba38).withValues(alpha: 0.5)),
                ),
                child: const Text(
                  '⚗ EXPERIMENT',
                  style: TextStyle(
                      fontSize: 10,
                      color: Color(0xFFffba38),
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8),
                ),
              ),
            ],
          ],
        ),
        actions: [
          // Experiment Mode toggle
          Tooltip(
            message: _experimentMode
                ? 'Exit experiment mode'
                : 'Experiment mode — try changes freely, restore anytime',
            child: IconButton(
              icon: Icon(
                Icons.science_outlined,
                color: _experimentMode
                    ? const Color(0xFFffba38)
                    : null,
              ),
              onPressed: () =>
                  setState(() => _experimentMode = !_experimentMode),
            ),
          ),
          // Config Library — browse community presets
          IconButton(
            icon: const Icon(Icons.library_books_outlined),
            tooltip: 'Config Library',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) =>
                    ConfigLibraryView(robotId: widget.rrn),
              ),
            ),
          ),
          // Flow / list view toggle
          IconButton(
            icon: Icon(
                _showFlow ? Icons.list : Icons.account_tree_outlined),
            tooltip:
                _showFlow ? 'List view' : 'Flow view',
            onPressed: () => setState(() => _showFlow = !_showFlow),
          ),
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
      body: Column(
          children: [
            // ── Experiment mode banner ───────────────────────────────
            if (_experimentMode)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                color: const Color(0xFF1a1400),
                child: Row(
                  children: [
                    const Text('⚗',
                        style: TextStyle(fontSize: 15)),
                    const SizedBox(width: 8),
                    const Expanded(
                      child: Text(
                        'Experiment mode — changes are not deployed. '
                        'Try anything freely.',
                        style: TextStyle(
                            color: Color(0xFFffba38),
                            fontSize: 12,
                            height: 1.4),
                      ),
                    ),
                    TextButton(
                      onPressed: _restoreToDeployed,
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFffba38),
                        textStyle: const TextStyle(fontSize: 11),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Restore deployed'),
                    ),
                  ],
                ),
              ),

            // ── Diff bar (changes vs deployed) ───────────────────────
            if (_hasUndeployedChanges && !_experimentMode)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                color: const Color(0xFF0e1a10),
                child: Row(
                  children: [
                    const Icon(Icons.edit_outlined,
                        size: 14, color: Color(0xFF4ade80)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _changeSummary.take(3).join('  ·  ') +
                            (_changeSummary.length > 3
                                ? '  · +${_changeSummary.length - 3} more'
                                : ''),
                        style: const TextStyle(
                            color: Color(0xFF4ade80),
                            fontSize: 11,
                            fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton(
                      onPressed: _restoreToDeployed,
                      style: TextButton.styleFrom(
                        foregroundColor: Colors.white38,
                        textStyle: const TextStyle(fontSize: 11),
                        visualDensity: VisualDensity.compact,
                      ),
                      child: const Text('Restore'),
                    ),
                  ],
                ),
              ),

            // ── Main editor body ─────────────────────────────────────
            Expanded(
              child: _showFlow
                  ? FlowCanvas(
                      layers: _config.layers,
                      graph: _flowGraph,
                      editable: true,
                      onGraphChanged: (g) =>
                          setState(() => _flowGraph = g),
                      onNodeTap: _openEditSheet,
                      onInsertOnEdge: _insertOnEdge,
                    )
                  : ListView(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              children: [
                // ── Community inspiration panel ──────────────────────
                _CommunityInspirationPanel(
                  onApplyPreset: (id, name) async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        backgroundColor: const Color(0xFF131c1f),
                        title: Text('Use "$name" as starting point?'),
                        content: Text(
                          'This will replace your current harness config '
                          'with the "$name" community preset. '
                          'You can continue editing after applying.',
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 13),
                        ),
                        actions: [
                          TextButton(
                              onPressed: () => Navigator.pop(ctx, false),
                              child: const Text('Cancel')),
                          FilledButton(
                              onPressed: () => Navigator.pop(ctx, true),
                              child: const Text('Apply')),
                        ],
                      ),
                    );
                    if (confirmed == true && mounted) {
                      Navigator.push(
                        context,
                        MaterialPageRoute<void>(
                          builder: (_) =>
                              ConfigLibraryView(robotId: widget.rrn),
                        ),
                      );
                    }
                  },
                  onOpenLibrary: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ConfigLibraryView(robotId: widget.rrn),
                    ),
                  ),
                  onApplyDimension: _applyFinding,
                ),
                // ── Harness pipeline layers ─────────────────────────
                HarnessViewer(
                  config: _config,
                  onEditLayer: _openEditSheet,
                  onToggleLayer: _toggleLayerEnabled,
                  onReorderSkills: _reorderSkills,
                  onAddSkill: _showSkillBrowser,
                ),
              ],
            ),
            ),  // Expanded
          ],    // Column children
        ),      // Column (body)
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
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final int? layerIndex;
  final int totalLayers;

  const _LayerEditPanel({
    super.key,
    required this.rrn,
    required this.layer,
    required this.onToggle,
    required this.onConfigChanged,
    required this.onClose,
    this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
    this.layerIndex,
    this.totalLayers = 0,
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.layer.label,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 15),
                    ),
                    if (widget.layer.canReorder && widget.layerIndex != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(
                          'Block ${widget.layerIndex! + 1} of ${widget.totalLayers}',
                          style: TextStyle(
                            fontSize: 10,
                            color: cs.onSurfaceVariant,
                            fontFamily: 'Space Grotesk',
                          ),
                        ),
                      ),
                  ],
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
              // ↑/↓ move buttons (reorderable layers only)
              if (widget.layer.canReorder) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_upward_rounded, size: 16),
                  tooltip: 'Move block up',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onMoveUp,
                ),
                IconButton(
                  icon: const Icon(Icons.arrow_downward_rounded, size: 16),
                  tooltip: 'Move block down',
                  visualDensity: VisualDensity.compact,
                  onPressed: widget.onMoveDown,
                ),
              ],
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
        _CommunityHint(
          fieldName: 'fast_model',
          hints: const {
            'Champion': 'gemini-2.5-flash',
            'Local Only': 'gemma3:1b (ollama)',
            'Industrial': 'gemini-2.5-flash',
            'Home': 'gemma3:1b (local)',
            'Quality First': 'claude-sonnet-4-6',
          },
          onApplyValue: (dim, val) {
            // Strip annotation like " (ollama)" before applying
            final clean = val.contains(' ') ? val.split(' ').first : val;
            widget.onUpdate('fast_model', clean);
          },
        ),
        const Text(
          '💡 Local models (gemma3:1b) win on home tasks where '
          'latency < 0.5s matters more than raw intelligence. '
          'Cloud models dominate industrial and general reasoning.',
          style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.5),
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
        const SizedBox(height: 4),
        _CommunityHint(
          fieldName: 'drift_detection',
          hints: const {
            'Champion': 'true',
            'Local Only': 'true',
            'Industrial': 'true',
            'Home': 'true',
          },
          onApplyValue: (dim, val) =>
              onUpdate('drift_detection', val == 'true'),
        ),
        const Text(
          '💡 All community presets enable drift detection — '
          'it catches model degradation in long sessions at near-zero cost.',
          style: TextStyle(fontSize: 11, color: Colors.white38, height: 1.5),
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
          Navigator.pop(context);
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
          Navigator.pop(context);
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
          Navigator.pop(context);
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
          Navigator.pop(context);
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
      _BlockEntry(
        emoji: '❓',
        title: 'Conditional Branch',
        subtitle: 'Route execution based on a condition (YES/NO)',
        onAdd: () {
          final id = 'cond-${DateTime.now().millisecondsSinceEpoch}';
          Navigator.pop(context);
          onAddLayer(HarnessLayer(
            id: id,
            type: 'conditional',
            label: 'If / Else',
            description: 'Branch on a condition expression',
            enabled: true,
            config: const {
              'condition': 'confidence > 0.7',
              'yes_next': '',
              'no_next': '',
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '🔁',
        title: 'Retry Loop',
        subtitle: 'Retry a step up to N times on failure',
        onAdd: () {
          final id = 'loop-${DateTime.now().millisecondsSinceEpoch}';
          Navigator.pop(context);
          onAddLayer(HarnessLayer(
            id: id,
            type: 'loop',
            label: 'Retry Loop',
            description: 'Retry on failure, up to max_retries times',
            enabled: true,
            config: const {
              'max_retries': 3,
              'retry_on': 'error',
              'backoff_s': 1,
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '🧑',
        title: 'HITL Gate',
        subtitle: 'Pause for human approval before proceeding',
        onAdd: () {
          final id = 'hitl-${DateTime.now().millisecondsSinceEpoch}';
          Navigator.pop(context);
          onAddLayer(HarnessLayer(
            id: id,
            type: 'hitl',
            label: 'Human Gate',
            description: 'Requires operator approval to continue',
            enabled: true,
            config: const {
              'timeout_s': 30,
              'on_timeout': 'block',
              'require_auth': true,
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '⑂',
        title: 'Parallel Fork',
        subtitle: 'Execute multiple branches concurrently',
        onAdd: () {
          final id = 'parallel-${DateTime.now().millisecondsSinceEpoch}';
          Navigator.pop(context);
          onAddLayer(HarnessLayer(
            id: id,
            type: 'parallel',
            label: 'Parallel Fork',
            description: 'Fan out to concurrent execution branches',
            enabled: true,
            config: const {
              'branches': [],
              'join_strategy': 'all',
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '🛡️',
        title: 'Circuit Breaker',
        subtitle: 'Disable a skill after repeated failures',
        onAdd: () {
          final id = 'circuit-${DateTime.now().millisecondsSinceEpoch}';
          Navigator.pop(context);
          onAddLayer(HarnessLayer(
            id: id,
            type: 'circuit_breaker',
            label: 'Circuit Breaker',
            description: 'Open circuit after N failures, auto-reset after cooldown',
            enabled: true,
            config: const {
              'failure_threshold': 3,
              'cooldown_s': 30,
              'half_open_probe': true,
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '💰',
        title: 'Cost Gate',
        subtitle: 'Halt if LLM spend exceeds budget',
        onAdd: () {
          final id = 'cost-${DateTime.now().millisecondsSinceEpoch}';
          Navigator.pop(context);
          onAddLayer(HarnessLayer(
            id: id,
            type: 'cost_gate',
            label: 'Cost Gate',
            description: 'Block execution if budget_usd ceiling is exceeded',
            enabled: true,
            config: const {
              'budget_usd': 0.10,
              'on_exceed': 'block',
              'alert_at_pct': 80,
            },
          ));
        },
      ),
      _BlockEntry(
        emoji: '📤',
        title: 'Dead Letter Queue',
        subtitle: 'Capture failed commands for human review',
        onAdd: () {
          if (config.layers.any((l) => l.id == 'dlq')) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('DLQ is already in this harness'),
                  behavior: SnackBarBehavior.floating),
            );
            return;
          }
          Navigator.pop(context);
          onAddLayer(const HarnessLayer(
            id: 'dlq',
            type: 'dlq',
            label: 'Dead Letter Queue',
            description: 'Failed commands queued for human review',
            enabled: true,
            config: {'db_path': 'dlq.db', 'max_size': 500},
          ));
        },
      ),
      _BlockEntry(
        emoji: '🔍',
        title: 'Span Tracer',
        subtitle: 'OpenTelemetry-style execution traces',
        onAdd: () {
          if (config.layers.any((l) => l.id == 'span-tracer')) {
            Navigator.pop(context);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                  content: Text('Span Tracer already added'),
                  behavior: SnackBarBehavior.floating),
            );
            return;
          }
          Navigator.pop(context);
          onAddLayer(const HarnessLayer(
            id: 'span-tracer',
            type: 'tracer',
            label: 'Span Tracer',
            description: 'Records execution spans for debugging and audit',
            enabled: true,
            config: {'export': 'sqlite', 'db_path': 'traces.db'},
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

// ── Community Inspiration Panel ───────────────────────────────────────────────
//
// Shown inside the HarnessViewer list view (above the layer list) so users
// see shared harness patterns while editing their own pipeline.
// Tapping a preset shows how it configures each dimension, or opens the
// full Config Library to apply it as a starting point.

class _CommunityInspirationPanel extends StatefulWidget {
  const _CommunityInspirationPanel({
    required this.onApplyPreset,
    required this.onOpenLibrary,
    this.onApplyDimension,
  });

  final void Function(String presetId, String presetName) onApplyPreset;
  final VoidCallback onOpenLibrary;
  /// Called when the user taps "Try →" on a param chip inside the panel.
  final void Function(String configDim, dynamic value)? onApplyDimension;

  @override
  State<_CommunityInspirationPanel> createState() =>
      _CommunityInspirationPanelState();
}

class _CommunityInspirationPanelState
    extends State<_CommunityInspirationPanel> {
  bool _expanded = false;
  int _selected = 0;

  static const _presets = [
    _PresetSnippet(
      id: 'lower_cost',
      name: 'Lower Cost',
      emoji: '⚖️',
      tagline: 'Champion · all hardware',
      scoreLabel: '0.6541',
      scoreColor: Color(0xFFffba38),
      params: {
        'thinking_budget': '1024',
        'context_budget': '8192',
        'max_iterations': '6',
        'cost_gate_usd': '0.01',
        'drift_detection': 'true',
        'retry_on_error': 'true',
      },
      skillOrder: ['p66-consent', 'context-builder', 'model-router', 'skill-executor', 'error-handler'],
      bestFor: 'General · Home · Industrial',
      why: 'Winning config across all tiers. Strict cost gate prevents runaway API spend on Pi-class hardware.',
    ),
    _PresetSnippet(
      id: 'local_only',
      name: 'Local Only',
      emoji: '🔒',
      tagline: 'Fully offline · no API key',
      scoreLabel: '0.8103',
      scoreColor: Color(0xFF4ade80),
      params: {
        'thinking_budget': '512',
        'context_budget': '4096',
        'force_local': 'true',
        'local_model': 'gemma3:1b',
        'cost_gate_usd': '0.00',
        'drift_detection': 'true',
      },
      skillOrder: ['p66-consent', 'local-model-router', 'skill-executor'],
      bestFor: 'Home',
      why: 'Removes the cloud model-router layer entirely. '
          'Sub-second latency for grip calls and appliance control.',
    ),
    _PresetSnippet(
      id: 'industrial_optimized',
      name: 'Industrial',
      emoji: '🏭',
      tagline: '+12% industrial median',
      scoreLabel: '0.8812',
      scoreColor: Color(0xFF4ade80),
      params: {
        'thinking_budget': '2048',
        'context_budget': '16384',
        'max_iterations': '8',
        'retry_on_error': 'true',
        'drift_detection': 'true',
        'cost_gate_usd': '0.10',
      },
      skillOrder: ['p66-consent', 'context-builder', 'model-router', 'alert-hook', 'skill-executor', 'error-handler', 'retry-hook'],
      bestFor: 'Industrial',
      why: 'retry_on_error is the single biggest lever for industrial tasks. '
          'alert-hook and retry-hook added after model-router.',
    ),
    _PresetSnippet(
      id: 'home_optimized',
      name: 'Home',
      emoji: '🏠',
      tagline: 'Low-latency · strict P66',
      scoreLabel: '0.8644',
      scoreColor: Color(0xFF4ade80),
      params: {
        'thinking_budget': '512',
        'context_budget': '4096',
        'max_iterations': '4',
        'retry_on_error': 'false',
        'local_model': 'gemma3:1b',
        'cost_gate_usd': '0.02',
      },
      skillOrder: ['p66-consent', 'local-model-router', 'grip-hook', 'skill-executor'],
      bestFor: 'Home',
      why: 'Grip-hook placed immediately after model router so P66 consent '
          'and grip calls happen in the same pass — minimises latency.',
    ),
    _PresetSnippet(
      id: 'quality_first',
      name: 'Quality First',
      emoji: '☁️',
      tagline: 'Server / cloud · max score',
      scoreLabel: '0.9801',
      scoreColor: Color(0xFF55d7ed),
      params: {
        'thinking_budget': '4096',
        'context_budget': '32768',
        'max_iterations': '8',
        'retry_on_error': 'true',
        'drift_detection': 'true',
        'cost_gate_usd': '1.00',
      },
      skillOrder: ['p66-consent', 'context-builder', 'model-router', 'skill-executor', 'error-handler', 'retry-hook', 'audit-logger'],
      bestFor: 'Industrial · General',
      why: 'Full layer stack with audit-logger at the end. '
          'No cost constraints — prioritises OHB-1 score over spend.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final preset = _presets[_selected];

    return Container(
      margin: const EdgeInsets.fromLTRB(0, 0, 0, 12),
      decoration: BoxDecoration(
        color: const Color(0xFF131c1f),
        border: Border.all(color: const Color(0xFF55d7ed).withValues(alpha: 0.18)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header (always visible) ───────────────────────────────
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  const Text('💡', style: TextStyle(fontSize: 16)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Inspired by shared harnesses',
                          style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13,
                              color: Color(0xFF55d7ed)),
                        ),
                        Text(
                          'See how community configs order skills and set parameters',
                          style: TextStyle(
                              fontSize: 11,
                              color: Colors.white38),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less : Icons.expand_more,
                    color: Colors.white38,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),

          if (_expanded) ...[
            const Divider(height: 1, color: Color(0xFF1a2527)),

            // ── Preset selector tabs ───────────────────────────────
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
              child: Row(
                children: List.generate(_presets.length, (i) {
                  final p = _presets[i];
                  final active = i == _selected;
                  return GestureDetector(
                    onTap: () => setState(() => _selected = i),
                    child: Container(
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 7),
                      decoration: BoxDecoration(
                        color: active
                            ? const Color(0xFF55d7ed).withValues(alpha: 0.12)
                            : Colors.transparent,
                        border: Border.all(
                          color: active
                              ? const Color(0xFF55d7ed).withValues(alpha: 0.5)
                              : Colors.white.withValues(alpha: 0.1),
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(p.emoji,
                              style: const TextStyle(fontSize: 13)),
                          const SizedBox(width: 5),
                          Text(p.name,
                              style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: active
                                      ? FontWeight.w700
                                      : FontWeight.normal,
                                  color: active
                                      ? const Color(0xFF55d7ed)
                                      : Colors.white70)),
                        ],
                      ),
                    ),
                  );
                }),
              ),
            ),

            // ── Selected preset detail ─────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text(preset.tagline,
                              style: const TextStyle(
                                  fontSize: 11, color: Colors.white38)),
                          const SizedBox(width: 8),
                          Text(preset.scoreLabel,
                              style: TextStyle(
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: preset.scoreColor)),
                          const Text(' OHB-1',
                              style: TextStyle(
                                  fontSize: 10, color: Colors.white38)),
                        ]),
                        const SizedBox(height: 6),
                        // Skill order
                        const Text('Skill order:',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.white38,
                                fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: List.generate(
                              preset.skillOrder.length,
                              (i) => Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF1a2527),
                                      borderRadius:
                                          BorderRadius.circular(6),
                                      border: Border.all(
                                          color: Colors.white
                                              .withValues(alpha: 0.1)),
                                    ),
                                    child: Text(
                                      preset.skillOrder[i],
                                      style: const TextStyle(
                                          fontFamily: 'monospace',
                                          fontSize: 10,
                                          color: Color(0xFF55d7ed)),
                                    ),
                                  ),
                                  if (i < preset.skillOrder.length - 1)
                                    const Padding(
                                      padding: EdgeInsets.symmetric(
                                          horizontal: 4),
                                      child: Text('→',
                                          style: TextStyle(
                                              color: Colors.white24,
                                              fontSize: 11)),
                                    ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Key params
                  SizedBox(
                    width: 160,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: preset.params.entries
                          .map((e) => GestureDetector(
                                onTap: widget.onApplyDimension != null
                                    ? () {
                                        // Parse value: booleans, numbers, strings
                                        dynamic parsed = e.value;
                                        if (e.value == 'true') {
                                          parsed = true;
                                        } else if (e.value == 'false') {
                                          parsed = false;
                                        } else {
                                          final n = num.tryParse(e.value);
                                          if (n != null) parsed = n;
                                        }
                                        widget.onApplyDimension!(
                                            e.key, parsed);
                                      }
                                    : null,
                                child: Padding(
                                  padding:
                                      const EdgeInsets.only(bottom: 3),
                                  child: Row(
                                    children: [
                                      Expanded(
                                          child: Text(e.key,
                                              style: const TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.white38,
                                                  fontFamily:
                                                      'monospace'))),
                                      Text(e.value,
                                          style: TextStyle(
                                              fontSize: 10,
                                              color: preset.scoreColor,
                                              fontFamily: 'monospace',
                                              fontWeight:
                                                  FontWeight.w600)),
                                      if (widget.onApplyDimension !=
                                          null) ...[
                                        const SizedBox(width: 4),
                                        const Text(
                                          '↑',
                                          style: TextStyle(
                                              fontSize: 9,
                                              color: Color(0xFFffba38)),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ))
                          .toList(),
                    ),
                  ),
                ],
              ),
            ),

            // ── Why it works ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
              child: Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFF0e1416),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '💡 ${preset.why}',
                  style: const TextStyle(
                      fontSize: 12,
                      color: Colors.white60,
                      height: 1.5),
                ),
              ),
            ),

            // ── Action row ────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: FilledButton(
                      onPressed: () =>
                          widget.onApplyPreset(preset.id, preset.name),
                      style: FilledButton.styleFrom(
                        backgroundColor:
                            const Color(0xFF55d7ed).withValues(alpha: 0.15),
                        foregroundColor: const Color(0xFF55d7ed),
                        side: const BorderSide(
                            color: Color(0xFF55d7ed), width: 1),
                      ),
                      child: Text('Use "${preset.name}" as starting point'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton(
                    onPressed: widget.onOpenLibrary,
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                          color: Colors.white.withValues(alpha: 0.15)),
                      foregroundColor: Colors.white54,
                    ),
                    child: const Text('All configs'),
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

class _PresetSnippet {
  const _PresetSnippet({
    required this.id,
    required this.name,
    required this.emoji,
    required this.tagline,
    required this.scoreLabel,
    required this.scoreColor,
    required this.params,
    required this.skillOrder,
    required this.bestFor,
    required this.why,
  });
  final String id;
  final String name;
  final String emoji;
  final String tagline;
  final String scoreLabel;
  final Color scoreColor;
  final Map<String, String> params;
  final List<String> skillOrder;
  final String bestFor;
  final String why;
}

// ── Community hint chip ───────────────────────────────────────────────────────
// Shown inline next to config fields to surface what community presets use.

class _CommunityHint extends StatelessWidget {
  const _CommunityHint({
    required this.fieldName,
    required this.hints,
    this.onApplyValue,
  });

  final String fieldName;
  // e.g. {'Champion': '1024', 'Industrial': '2048', 'Home': '512'}
  final Map<String, String> hints;
  // Optional callback: when provided, each chip gets a "Try →" tap target.
  // Called with the raw string value from the hint.
  final void Function(String configDim, String value)? onApplyValue;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Community: ',
                  style: TextStyle(fontSize: 10, color: Colors.white30)),
              Expanded(
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: hints.entries
                      .map((e) => GestureDetector(
                            onTap: onApplyValue != null
                                ? () => onApplyValue!(fieldName, e.value)
                                : null,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 7, vertical: 2),
                              decoration: BoxDecoration(
                                color: const Color(0xFF55d7ed)
                                    .withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(99),
                                border: Border.all(
                                    color: const Color(0xFF55d7ed)
                                        .withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${e.key}: ${e.value}',
                                    style: const TextStyle(
                                        fontSize: 10,
                                        color: Color(0xFF55d7ed),
                                        fontFamily: 'monospace'),
                                  ),
                                  if (onApplyValue != null) ...[
                                    const SizedBox(width: 4),
                                    const Text(
                                      'Try →',
                                      style: TextStyle(
                                          fontSize: 9,
                                          color: Color(0xFFffba38),
                                          fontWeight: FontWeight.w700),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          ))
                      .toList(),
                ),
              ),
            ],
          ),
          if (onApplyValue != null)
            const Padding(
              padding: EdgeInsets.only(top: 2),
              child: Text(
                'Tap a chip to try that value in your current config.',
                style: TextStyle(fontSize: 9, color: Colors.white24),
              ),
            ),
        ],
      ),
    );
  }
}
