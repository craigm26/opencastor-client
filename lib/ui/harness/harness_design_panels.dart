import 'package:flutter/material.dart';

/// Harness Designer v2 panels — Pattern, Memory, Security (#28).
/// Three collapsible ExpansionTile panels for advanced harness configuration.
/// Uses Theme.of(context).colorScheme — no hardcoded colors.

// ─── Pattern Panel ────────────────────────────────────────────────────────────

class PatternPanel extends StatefulWidget {
  const PatternPanel({super.key});

  @override
  State<PatternPanel> createState() => _PatternPanelState();
}

class _PatternPanelState extends State<PatternPanel> {
  String _pattern = 'single_agent_supervisor';
  String _ledgerPath = '/tmp/castor_ledger';
  String _mode = 'sequential';
  final List<String> _roles = ['planner', 'executor', 'verifier'];

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: Icon(Icons.account_tree_outlined, color: cs.primary),
      title: const Text('Orchestration Pattern',
          style: TextStyle(fontWeight: FontWeight.w600)),
      childrenPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _pattern,
          decoration: InputDecoration(
            labelText: 'Pattern',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: const [
            DropdownMenuItem(
                value: 'single_agent_supervisor',
                child: Text('Single Agent Supervisor')),
            DropdownMenuItem(
                value: 'initializer_executor',
                child: Text('Initializer / Executor')),
            DropdownMenuItem(
                value: 'multi_agent', child: Text('Multi-Agent')),
          ],
          onChanged: (v) => setState(() => _pattern = v!),
        ),
        if (_pattern == 'initializer_executor') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _ledgerPath,
            decoration: InputDecoration(
              labelText: 'Ledger path',
              hintText: '/tmp/castor_ledger',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (v) => setState(() => _ledgerPath = v),
          ),
        ],
        if (_pattern == 'multi_agent') ...[
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            children: _roles
                .map((r) => Chip(
                      label: Text(r),
                      backgroundColor: cs.secondaryContainer,
                      labelStyle:
                          TextStyle(color: cs.onSecondaryContainer),
                    ))
                .toList(),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(
                  value: 'sequential', label: Text('Sequential')),
              ButtonSegment(
                  value: 'parallel', label: Text('Parallel')),
            ],
            selected: {_mode},
            onSelectionChanged: (s) =>
                setState(() => _mode = s.first),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Memory Panel ─────────────────────────────────────────────────────────────

class MemoryPanel extends StatefulWidget {
  const MemoryPanel({super.key});

  @override
  State<MemoryPanel> createState() => _MemoryPanelState();
}

class _MemoryPanelState extends State<MemoryPanel> {
  String _backend = 'working_memory';
  String _path = '~/.castor/memory/';
  String _overflow = 'truncate';
  double _maxTokens = 2048;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: Icon(Icons.memory_outlined, color: cs.primary),
      title: const Text('Memory & Context',
          style: TextStyle(fontWeight: FontWeight.w600)),
      childrenPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          value: _backend,
          decoration: InputDecoration(
            labelText: 'Backend',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: const [
            DropdownMenuItem(
                value: 'working_memory', child: Text('Working Memory')),
            DropdownMenuItem(
                value: 'filesystem', child: Text('Filesystem')),
            DropdownMenuItem(
                value: 'firestore', child: Text('Firestore')),
          ],
          onChanged: (v) => setState(() => _backend = v!),
        ),
        if (_backend == 'filesystem') ...[
          const SizedBox(height: 12),
          TextFormField(
            initialValue: _path,
            decoration: InputDecoration(
              labelText: 'Memory path',
              hintText: '~/.castor/memory/',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (v) => setState(() => _path = v),
          ),
        ],
        const SizedBox(height: 12),
        DropdownButtonFormField<String>(
          value: _overflow,
          decoration: InputDecoration(
            labelText: 'Overflow strategy',
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8)),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          ),
          items: const [
            DropdownMenuItem(
                value: 'truncate', child: Text('Truncate')),
            DropdownMenuItem(
                value: 'summarize', child: Text('Summarize')),
            DropdownMenuItem(
                value: 'drop_oldest', child: Text('Drop Oldest')),
          ],
          onChanged: (v) => setState(() => _overflow = v!),
        ),
        const SizedBox(height: 12),
        Row(children: [
          Text('Max tokens: ${_maxTokens.toInt()}',
              style: TextStyle(color: cs.onSurfaceVariant)),
        ]),
        Slider(
          value: _maxTokens,
          min: 512,
          max: 8192,
          divisions: 15,
          label: _maxTokens.toInt().toString(),
          onChanged: (v) => setState(() => _maxTokens = v),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Security Panel ───────────────────────────────────────────────────────────

class SecurityPanel extends StatefulWidget {
  const SecurityPanel({super.key});

  @override
  State<SecurityPanel> createState() => _SecurityPanelState();
}

class _SecurityPanelState extends State<SecurityPanel> {
  bool _opaEnabled = false;
  String _opaUrl = 'http://localhost:8181';
  String _opaMode = 'audit';
  bool _telemetryEnabled = false;
  bool _stdoutBackend = true;
  bool _sqliteBackend = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ExpansionTile(
      leading: Icon(Icons.security_outlined, color: cs.primary),
      title: const Text('Security & Observability',
          style: TextStyle(fontWeight: FontWeight.w600)),
      childrenPadding:
          const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      expandedCrossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('OPA Guardrail'),
          subtitle: const Text('Policy-as-code action gate'),
          value: _opaEnabled,
          onChanged: (v) => setState(() => _opaEnabled = v),
        ),
        if (_opaEnabled) ...[
          TextFormField(
            initialValue: _opaUrl,
            decoration: InputDecoration(
              labelText: 'OPA URL',
              hintText: 'http://localhost:8181',
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            onChanged: (v) => setState(() => _opaUrl = v),
          ),
          const SizedBox(height: 12),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'audit', label: Text('Audit')),
              ButtonSegment(value: 'enforce', label: Text('Enforce')),
            ],
            selected: {_opaMode},
            onSelectionChanged: (s) =>
                setState(() => _opaMode = s.first),
          ),
          const SizedBox(height: 8),
        ],
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Telemetry'),
          subtitle: const Text('Token cost tracking & alerts'),
          value: _telemetryEnabled,
          onChanged: (v) => setState(() => _telemetryEnabled = v),
        ),
        if (_telemetryEnabled) ...[
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('stdout'),
            value: _stdoutBackend,
            onChanged: (v) =>
                setState(() => _stdoutBackend = v ?? false),
          ),
          CheckboxListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('sqlite (~/.castor/telemetry.db)'),
            value: _sqliteBackend,
            onChanged: (v) =>
                setState(() => _sqliteBackend = v ?? false),
          ),
        ],
        const SizedBox(height: 8),
      ],
    );
  }
}

// ─── Combined widget ──────────────────────────────────────────────────────────

class HarnessDesignPanels extends StatelessWidget {
  const HarnessDesignPanels({super.key});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
          child: Text(
            'Advanced Configuration',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: cs.onSurfaceVariant,
              letterSpacing: 0.5,
            ),
          ),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: const PatternPanel(),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: const MemoryPanel(),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: const SecurityPanel(),
        ),
        Card(
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: const VisualPlannerPanel(),
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

// ─── Visual Planner Panel ─────────────────────────────────────────────────────

class VisualPlannerPanel extends StatefulWidget {
  const VisualPlannerPanel({super.key});

  @override
  State<VisualPlannerPanel> createState() => _VisualPlannerPanelState();
}

class _VisualPlannerPanelState extends State<VisualPlannerPanel> {
  String _model = 'none';
  String _goalSource = 'oak_d';
  int _planningHorizon = 16;
  int _cemSamples = 512;
  String _device = 'hailo';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ExpansionTile(
      leading: Icon(Icons.remove_red_eye_outlined, color: cs.primary),
      title: const Text('Visual Planner'),
      subtitle: Text(
        _model == 'none'
            ? 'Disabled — LLM handles motor planning'
            : 'LeWM JEPA — pixel-based motor planning',
        style: const TextStyle(fontSize: 12),
      ),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Model selection
              const Text('Model backend',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 6),
              SegmentedButton<String>(
                segments: const [
                  ButtonSegment(value: 'none', label: Text('None (LLM)')),
                  ButtonSegment(value: 'lewm', label: Text('LeWM')),
                  ButtonSegment(value: 'dinowm', label: Text('DINO-WM')),
                ],
                selected: {_model},
                onSelectionChanged: (s) => setState(() => _model = s.first),
              ),
              const SizedBox(height: 12),

              // LeWM info card
              if (_model == 'lewm') ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF55d7ed).withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF55d7ed).withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        '⚗ LeWorldModel (LeWM)',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF55d7ed),
                            fontSize: 13),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        '15M params · raw pixels · ~1s on Pi5+Hailo8L\n'
                        'JEPA architecture — no text LLM needed for motor tasks.\n'
                        'Routes grip / navigate / place / reach commands through\n'
                        'pixel-based planning instead of the model router.',
                        style: TextStyle(
                            fontSize: 12, color: Colors.white70, height: 1.5),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(Icons.check_circle_outline,
                              size: 13, color: Color(0xFF4ade80)),
                          const SizedBox(width: 4),
                          const Text(
                            'Fully offline · no API key · OAK-D native',
                            style: TextStyle(
                                fontSize: 11, color: Color(0xFF4ade80)),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Goal source
                const Text('Goal source',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                DropdownButtonFormField<String>(
                  value: _goalSource,
                  isDense: true,
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'oak_d', child: Text('OAK-D (live frame)')),
                    DropdownMenuItem(
                        value: 'last_frame', child: Text('Last captured frame')),
                    DropdownMenuItem(
                        value: 'static_image',
                        child: Text('Static image (set manually)')),
                  ],
                  onChanged: (v) => setState(() => _goalSource = v!),
                ),
                const SizedBox(height: 12),

                // Planning horizon
                Text('Planning horizon: $_planningHorizon steps',
                    style: const TextStyle(fontSize: 12)),
                Slider(
                  value: _planningHorizon.toDouble(),
                  min: 4,
                  max: 64,
                  divisions: 15,
                  label: '$_planningHorizon',
                  onChanged: (v) =>
                      setState(() => _planningHorizon = v.round()),
                ),
                const _VisualHint(
                  'Research: horizon=16 balances planning quality vs latency on Pi-class hardware.'),

                // CEM samples
                Text('CEM samples: $_cemSamples',
                    style: const TextStyle(fontSize: 12)),
                Slider(
                  value: _cemSamples.toDouble(),
                  min: 64,
                  max: 1024,
                  divisions: 15,
                  label: '$_cemSamples',
                  onChanged: (v) =>
                      setState(() => _cemSamples = v.round()),
                ),
                const _VisualHint(
                  'More samples = better action quality, higher latency. '
                  '512 is the autoresearch default.'),

                // Device
                const Text('Inference device',
                    style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600)),
                DropdownButtonFormField<String>(
                  value: _device,
                  isDense: true,
                  decoration: const InputDecoration(
                      isDense: true, border: OutlineInputBorder()),
                  items: const [
                    DropdownMenuItem(
                        value: 'hailo',
                        child: Text('Hailo8L (Pi5+Hailo, recommended)')),
                    DropdownMenuItem(
                        value: 'cpu', child: Text('CPU (~8–15s on Pi)')),
                    DropdownMenuItem(
                        value: 'cuda', child: Text('CUDA (server/Jetson)')),
                  ],
                  onChanged: (v) => setState(() => _device = v!),
                ),
              ],

              if (_model == 'dinowm')
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: const Text(
                    'DINO-WM: heavier baseline (~47s planning). '
                    'Use for comparison against LeWM. '
                    'Not recommended for real-time use on Pi-class hardware.',
                    style: TextStyle(
                        fontSize: 12, color: Colors.white54, height: 1.5),
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _VisualHint extends StatelessWidget {
  const _VisualHint(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(
          '💡 $text',
          style: const TextStyle(
              fontSize: 11, color: Colors.white38, height: 1.5),
        ),
      );
}
