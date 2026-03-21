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
        const SizedBox(height: 16),
      ],
    );
  }
}
