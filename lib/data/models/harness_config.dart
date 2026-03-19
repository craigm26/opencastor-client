/// HarnessConfig — data model for the AgentHarness pipeline configuration.
///
/// Mirrors the RCAN `agent.harness` section from the OpenCastor backend
/// (castor/harness.py).  Used by HarnessViewer and HarnessEditor.
library;

/// A single layer in the harness pipeline.
class HarnessLayer {
  const HarnessLayer({
    required this.id,
    required this.type,
    required this.label,
    required this.description,
    required this.enabled,
    this.canDisable = true,
    this.canReorder = true,
    this.config = const {},
  });

  /// Unique layer identifier, e.g. 'hook-p66', 'skill-navigate-to'.
  final String id;

  /// Layer type: 'skill' | 'hook' | 'context' | 'model' | 'trajectory'.
  final String type;

  /// Human-readable display label.
  final String label;

  /// Short description shown in the viewer.
  final String description;

  /// Whether this layer is currently enabled.
  final bool enabled;

  /// False for P66 — it cannot be disabled.
  final bool canDisable;

  /// False for P66 (always first) and trajectory (always last).
  final bool canReorder;

  /// Layer-specific config values (provider, model, threshold, path, etc.).
  final Map<String, dynamic> config;

  HarnessLayer copyWith({
    bool? enabled,
    Map<String, dynamic>? config,
  }) {
    return HarnessLayer(
      id: id,
      type: type,
      label: label,
      description: description,
      enabled: enabled ?? this.enabled,
      canDisable: canDisable,
      canReorder: canReorder,
      config: config ?? this.config,
    );
  }

  Map<String, dynamic> toMap() => {
        'id': id,
        'type': type,
        'label': label,
        'description': description,
        'enabled': enabled,
        'can_disable': canDisable,
        'can_reorder': canReorder,
        'config': config,
      };

  /// Alias for [toMap] — used by harness validator CF call serialisation.
  Map<String, dynamic> toJson() => toMap();

  factory HarnessLayer.fromMap(Map<String, dynamic> map) => HarnessLayer(
        id: map['id'] as String? ?? '',
        type: map['type'] as String? ?? 'skill',
        label: map['label'] as String? ?? '',
        description: map['description'] as String? ?? '',
        enabled: map['enabled'] as bool? ?? true,
        canDisable: map['can_disable'] as bool? ?? true,
        canReorder: map['can_reorder'] as bool? ?? true,
        config: Map<String, dynamic>.from(
            (map['config'] as Map?)?.cast<String, dynamic>() ?? {}),
      );
}

/// Full harness configuration for a robot.
class HarnessConfig {
  const HarnessConfig({
    required this.robotRrn,
    required this.name,
    required this.layers,
  });

  /// The RRN of the robot this config belongs to.
  final String robotRrn;

  /// Friendly name for this configuration (used when saving as template).
  final String name;

  /// Ordered list of harness layers.
  final List<HarnessLayer> layers;

  // ── Convenience accessors ──────────────────────────────────────────────

  List<HarnessLayer> get skillLayers =>
      layers.where((l) => l.type == 'skill').toList();

  List<HarnessLayer> get hookLayers =>
      layers.where((l) => l.type == 'hook').toList();

  HarnessLayer? get contextLayer =>
      layers.where((l) => l.type == 'context').firstOrNull;

  HarnessLayer? get modelLayer =>
      layers.where((l) => l.type == 'model').firstOrNull;

  HarnessLayer? get trajectoryLayer =>
      layers.where((l) => l.type == 'trajectory').firstOrNull;

  // ── Default harness (mirrors castor/harness.py defaults) ──────────────

  static HarnessConfig defaults({String robotRrn = ''}) => HarnessConfig(
        robotRrn: robotRrn,
        name: 'Advanced Agent Harness',
        layers: [
          // ── ALWAYS-ON SAFETY INVARIANTS ───────────────────────────────────
          const HarnessLayer(
            id: 'hook-p66',
            type: 'hook',
            label: 'P66 Safety',
            description: 'ESTOP bypass · Scope enforcement · Physical consent',
            enabled: true,
            canDisable: false,
            canReorder: false,
            config: {'p66_audit': true},
          ),

          // ── SECURITY & VALIDATION ─────────────────────────────────────────
          const HarnessLayer(
            id: 'prompt-guard',
            type: 'guard',
            label: 'Prompt Guard',
            description: 'Blocks jailbreak, injection, and role-switch attempts',
            enabled: true,
            config: {
              'block_jailbreak': true,
              'block_injection': true,
              'block_role_switch': true,
              'risk_threshold': 0.6,
            },
          ),

          // ── CONTEXT ASSEMBLY ──────────────────────────────────────────────
          const HarnessLayer(
            id: 'context-builder',
            type: 'context',
            label: 'Context Builder',
            description: 'Memory · Telemetry · Skills · System prompt',
            enabled: true,
            canDisable: false,
            canReorder: false,
            config: {
              'memory': true,
              'telemetry': true,
              'system_prompt': true,
              'skills_context': true,
              'rcan_identity': true,
            },
          ),

          // ── WORKING MEMORY ────────────────────────────────────────────────
          const HarnessLayer(
            id: 'working-memory',
            type: 'memory',
            label: 'Working Memory',
            description: 'Per-session scratchpad for multi-step reasoning',
            enabled: true,
            config: {
              'max_entries': 50,
              'ttl_s': 1800,
              'persist': false,
            },
          ),

          // ── SKILLS ────────────────────────────────────────────────────────
          HarnessLayer(
            id: 'skill-navigate-to',
            type: 'skill',
            label: 'navigate-to',
            description: 'Autonomous waypoint navigation',
            enabled: true,
            config: const {'order': 0},
          ),
          HarnessLayer(
            id: 'skill-camera-describe',
            type: 'skill',
            label: 'camera-describe',
            description: 'Describe scene from camera feed',
            enabled: true,
            config: const {'order': 1},
          ),
          HarnessLayer(
            id: 'skill-web-lookup',
            type: 'skill',
            label: 'web-lookup',
            description: 'Web search and knowledge retrieval',
            enabled: true,
            config: const {'order': 2},
          ),
          HarnessLayer(
            id: 'skill-arm-manipulate',
            type: 'skill',
            label: 'arm-manipulate',
            description: 'Arm/gripper manipulation primitives',
            enabled: false,
            config: const {'order': 3},
          ),
          HarnessLayer(
            id: 'skill-peer-coordinate',
            type: 'skill',
            label: 'peer-coordinate',
            description: 'Multi-robot coordination via RCAN',
            enabled: false,
            config: const {'order': 4},
          ),

          // ── CONFIDENCE & SAFETY GATES ─────────────────────────────────────
          const HarnessLayer(
            id: 'circuit-breaker',
            type: 'circuit_breaker',
            label: 'Circuit Breaker',
            description: 'Disables skills after 3 failures; resets after 30s',
            enabled: true,
            config: {
              'failure_threshold': 3,
              'cooldown_s': 30,
              'half_open_probe': true,
            },
          ),
          const HarnessLayer(
            id: 'hitl-physical',
            type: 'hitl',
            label: 'Physical HITL Gate',
            description: 'Operator approval required for physical actions',
            enabled: true,
            config: {
              'timeout_s': 30,
              'on_timeout': 'block',
              'require_auth': true,
              'action_types': ['move', 'actuate', 'grip', 'rotate', 'extend', 'retract'],
            },
          ),

          // ── MODEL ROUTING ─────────────────────────────────────────────────
          const HarnessLayer(
            id: 'model-dual',
            type: 'model',
            label: 'Dual Model',
            description: 'Fast local (Gemma 3) · Slow cloud (Gemini 2.5) by confidence',
            enabled: true,
            canDisable: false,
            canReorder: false,
            config: {
              'fast_provider': 'ollama',
              'fast_model': 'gemma3:1b',
              'slow_provider': 'google',
              'slow_model': 'gemini-2.5-flash',
              'confidence_threshold': 0.72,
            },
          ),

          // ── COST & DRIFT MONITORING ───────────────────────────────────────
          const HarnessLayer(
            id: 'cost-gate',
            type: 'cost_gate',
            label: 'Cost Gate',
            description: r'Halts if LLM spend exceeds $0.10/session',
            enabled: true,
            config: {
              'budget_usd': 0.10,
              'on_exceed': 'block',
              'alert_at_pct': 80,
            },
          ),
          const HarnessLayer(
            id: 'hook-drift',
            type: 'hook',
            label: 'Drift Detection',
            description: 'Detects model off-task drift after 3+ iterations',
            enabled: true,
            config: {'drift_threshold': 0.15},
          ),

          // ── OBSERVABILITY ─────────────────────────────────────────────────
          const HarnessLayer(
            id: 'span-tracer',
            type: 'tracer',
            label: 'Span Tracer',
            description: 'OpenTelemetry-style execution traces → SQLite',
            enabled: true,
            config: {'export': 'sqlite', 'db_path': 'traces.db'},
          ),
          const HarnessLayer(
            id: 'dlq',
            type: 'dlq',
            label: 'Dead Letter Queue',
            description: 'Failed commands queued for human review',
            enabled: true,
            config: {'db_path': 'dlq.db', 'max_size': 500},
          ),

          // ── AUDIT (always-on, always last) ────────────────────────────────
          const HarnessLayer(
            id: 'trajectory-logger',
            type: 'trajectory',
            label: 'Trajectory Logger',
            description:
                'Always-on audit trail — every run logged to SQLite. '
                'Required for autoresearch and RCAN compliance.',
            enabled: true,
            canDisable: false,
            canReorder: false,
            config: {'sqlite_path': 'trajectory.db'},
          ),
        ],
      );

  // ── Parse from RCAN YAML map ──────────────────────────────────────────

  factory HarnessConfig.fromYaml(Map<String, dynamic> yaml, String rrn) {
    final agentSection = yaml['agent'] as Map? ?? {};
    final harnessSection = agentSection['harness'] as Map? ?? {};
    final skillsSection = yaml['skills'] as Map? ?? {};
    final hooksSection = harnessSection['hooks'] as Map? ?? {};
    final contextSection = harnessSection['context'] as Map? ?? {};
    final modelSection = yaml['model_tiers'] as Map? ?? agentSection;
    final trajectorySection = harnessSection['trajectory'] as Map? ?? {};

    final layers = <HarnessLayer>[];

    // P66 hook — always on
    layers.add(HarnessLayer(
      id: 'hook-p66',
      type: 'hook',
      label: 'P66 Safety',
      description: 'ESTOP bypass · Scope enforcement · Physical consent',
      enabled: true,
      canDisable: false,
      canReorder: false,
      config: {'p66_audit': hooksSection['p66_audit'] as bool? ?? true},
    ));

    // Context builder
    layers.add(HarnessLayer(
      id: 'context-builder',
      type: 'context',
      label: 'Context Builder',
      description: 'Assembles memory, telemetry, and skill context',
      enabled: true,
      canDisable: false,
      canReorder: false,
      config: {
        'memory': contextSection['memory'] as bool? ?? true,
        'telemetry': contextSection['telemetry'] as bool? ??
            (agentSection['auto_telemetry'] as bool? ?? true),
        'system_prompt': contextSection['system_prompt'] as bool? ?? true,
        'skills_context': contextSection['skills_context'] as bool? ?? true,
      },
    ));

    // Skills
    final skillNames = [
      'navigate-to',
      'camera-describe',
      'arm-manipulate',
      'web-lookup',
      'peer-coordinate',
      'code-reviewer',
    ];
    final skillsEnabled =
        skillsSection.isNotEmpty ? skillsSection : <String, dynamic>{};
    for (var i = 0; i < skillNames.length; i++) {
      final name = skillNames[i];
      final skillKey = name.replaceAll('-', '_');
      final skillConfig = skillsEnabled[skillKey] as Map? ?? {};
      layers.add(HarnessLayer(
        id: 'skill-$name',
        type: 'skill',
        label: name,
        description: _skillDescription(name),
        enabled: skillConfig['enabled'] as bool? ?? false,
        config: {'order': i, ...Map<String, dynamic>.from(skillConfig)},
      ));
    }

    // Dual model
    layers.add(HarnessLayer(
      id: 'model-dual',
      type: 'model',
      label: 'Dual Model',
      description: 'Fast and slow model routing by confidence',
      enabled: true,
      canDisable: false,
      canReorder: false,
      config: {
        'fast_provider': modelSection['fast_provider'] as String? ?? 'ollama',
        'fast_model': modelSection['fast_model'] as String? ?? 'gemma3:1b',
        'slow_provider':
            modelSection['slow_provider'] as String? ?? 'google',
        'slow_model': modelSection['slow_model'] as String? ??
            agentSection['model'] as String? ??
            'gemini-2.0-flash',
        'confidence_threshold':
            (modelSection['confidence_threshold'] as num?)?.toDouble() ?? 0.7,
      },
    ));

    // Drift detection hook
    layers.add(HarnessLayer(
      id: 'hook-drift',
      type: 'hook',
      label: 'Drift Detection',
      description: 'Detects model off-task drift after 3+ iterations',
      enabled: hooksSection['drift_detection'] as bool? ?? true,
      config: {
        'drift_threshold':
            (hooksSection['drift_threshold'] as num?)?.toDouble() ?? 0.15,
      },
    ));

    // Trajectory logger — always on, always last
    layers.add(HarnessLayer(
      id: 'trajectory-logger',
      type: 'trajectory',
      label: 'Trajectory Logger',
      description:
          'Always-on audit trail — every run logged to SQLite. '
          'Required for autoresearch and RCAN compliance.',
      enabled: true,
      canDisable: false,
      canReorder: false,
      config: {
        'sqlite_path':
            trajectorySection['sqlite_path'] as String? ?? 'trajectory.db',
      },
    ));

    return HarnessConfig(
      robotRrn: rrn,
      name: (yaml['metadata'] as Map?)?['robot_name'] as String? ??
          'Robot Harness',
      layers: layers,
    );
  }

  static String _skillDescription(String name) {
    switch (name) {
      case 'navigate-to':
        return 'Autonomous waypoint navigation';
      case 'camera-describe':
        return 'Describe scene from camera feed';
      case 'arm-manipulate':
        return 'Arm/gripper manipulation primitives';
      case 'web-lookup':
        return 'Web search and knowledge retrieval';
      case 'peer-coordinate':
        return 'Multi-robot coordination via RCAN';
      case 'code-reviewer':
        return 'Code analysis and review tool';
      default:
        return name;
    }
  }

  // ── Serialize to YAML map for deployment ─────────────────────────────

  Map<String, dynamic> toYaml() {
    final skills = <String, dynamic>{};
    for (final layer in skillLayers) {
      final skillKey = layer.label.replaceAll('-', '_');
      skills[skillKey] = {
        'enabled': layer.enabled,
        ...layer.config,
      };
    }

    final ctxConfig = contextLayer?.config ?? {};
    final mdlConfig = modelLayer?.config ?? {};
    final driftLayer = layers.where((l) => l.id == 'hook-drift').firstOrNull;
    final trajConfig = trajectoryLayer?.config ?? {};

    return {
      'agent': {
        'harness': {
          'enabled': true,
          'max_iterations': 6,
          'context_budget': 0.8,
          'auto_rag': ctxConfig['memory'] as bool? ?? true,
          'auto_telemetry': ctxConfig['telemetry'] as bool? ?? true,
          'hooks': {
            'p66_audit': true,
            'retry_on_error': true,
            'drift_detection': driftLayer?.enabled ?? true,
            'drift_threshold':
                driftLayer?.config['drift_threshold'] ?? 0.15,
          },
          'context': {
            'memory': ctxConfig['memory'] ?? true,
            'telemetry': ctxConfig['telemetry'] ?? true,
            'system_prompt': ctxConfig['system_prompt'] ?? true,
            'skills_context': ctxConfig['skills_context'] ?? true,
          },
          'trajectory': {
            'enabled': trajectoryLayer?.enabled ?? true,
            'sqlite_path': trajConfig['sqlite_path'] ?? 'trajectory.db',
          },
        },
      },
      'skills': skills,
      'model_tiers': {
        'fast_provider': mdlConfig['fast_provider'] ?? 'ollama',
        'fast_model': mdlConfig['fast_model'] ?? 'gemma3:1b',
        'slow_provider': mdlConfig['slow_provider'] ?? 'google',
        'slow_model': mdlConfig['slow_model'] ?? 'gemini-2.0-flash',
        'confidence_threshold': mdlConfig['confidence_threshold'] ?? 0.7,
      },
    };
  }

  HarnessConfig copyWithLayers(List<HarnessLayer> newLayers) => HarnessConfig(
        robotRrn: robotRrn,
        name: name,
        layers: newLayers,
      );

  HarnessConfig copyWithName(String newName) => HarnessConfig(
        robotRrn: robotRrn,
        name: newName,
        layers: layers,
      );

  /// Returns a new config with [layer] inserted just before the trajectory
  /// logger (always-last), or appended if no trajectory layer is found.
  HarnessConfig withLayerAdded(HarnessLayer layer) {
    final newLayers = List<HarnessLayer>.from(layers);
    final trajIdx = newLayers.indexWhere((l) => l.type == 'trajectory');
    if (trajIdx >= 0) {
      newLayers.insert(trajIdx, layer);
    } else {
      newLayers.add(layer);
    }
    return copyWithLayers(newLayers);
  }

  /// Returns a new config with the layer matching [layerId] removed.
  /// P66 and trajectory layers are silently kept even if targeted.
  HarnessConfig withLayerRemoved(String layerId) {
    final removed = layers.firstWhere(
      (l) => l.id == layerId,
      orElse: () => const HarnessLayer(
        id: '', type: '', label: '', description: '', enabled: false,
      ),
    );
    // Never remove always-on invariant layers
    if (!removed.canDisable) return this;
    return copyWithLayers(layers.where((l) => l.id != layerId).toList());
  }
}
