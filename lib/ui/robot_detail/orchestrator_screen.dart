/// Orchestrator Management Screen — M2M_TRUSTED registration and consent flow.
/// Route: /robot/:rrn/orchestrators
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../../data/models/robot.dart';
import '../robot_detail/robot_detail_view_model.dart';
import '../core/theme/app_theme.dart';

const _rrfBaseUrl = 'https://api.rrf.rcan.dev';

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final orchestratorsProvider = FutureProvider.family<List<Map<String, dynamic>>, String>(
  (ref, rrn) async {
    // In production: fetch from RRF or Firestore
    // Returns pending + active orchestrators for this robot
    final resp = await http.get(
      Uri.parse('$_rrfBaseUrl/v2/orchestrators?fleet_rrn=$rrn'),
    );
    if (resp.statusCode == 200) {
      final data = jsonDecode(resp.body) as Map<String, dynamic>;
      return List<Map<String, dynamic>>.from(data['orchestrators'] as List? ?? []);
    }
    return [];
  },
);

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class OrchestratorScreen extends ConsumerWidget {
  final String rrn;
  const OrchestratorScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return Scaffold(
      appBar: AppBar(
        title: const Text('Orchestrators'),
        actions: [
          IconButton(
            icon: const Icon(Icons.add),
            tooltip: 'Register Orchestrator',
            onPressed: () => _showRegisterDialog(context, rrn),
          ),
        ],
      ),
      body: robotAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (robot) {
          if (robot == null) return const Center(child: Text('Robot not found'));
          return _OrchestratorList(robot: robot);
        },
      ),
    );
  }

  void _showRegisterDialog(BuildContext context, String rrn) {
    showDialog<void>(
      context: context,
      builder: (_) => _RegisterOrchestratorDialog(rrn: rrn),
    );
  }
}

// ---------------------------------------------------------------------------
// List view
// ---------------------------------------------------------------------------

class _OrchestratorList extends StatelessWidget {
  final Robot robot;
  const _OrchestratorList({required this.robot});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // Status banner
        if (!robot.isRcanV21)
          _InfoBanner(
            icon: Icons.info_outline,
            color: Colors.orange,
            message: 'Robot must run RCAN v2.1 to accept M2M_TRUSTED sessions.',
          ),

        const SizedBox(height: 8),
        Text('RCAN v2.1 §2.9 — M2M_TRUSTED Orchestrators',
            style: TextStyle(
                fontSize: 12, color: cs.onSurface.withOpacity(0.6))),
        const SizedBox(height: 4),
        Text(
          'Orchestrators are cross-fleet systems authorized by all robot owners to command '
          'multiple robots simultaneously. Each orchestrator must have consent from every '
          "robot owner. Tokens are issued by RRF's root key and expire in 24 hours.",
          style: TextStyle(fontSize: 12, color: cs.onSurface.withOpacity(0.6)),
        ),
        const SizedBox(height: 16),

        // Example pending consent card (would be populated from RRF API)
        _ConsentPendingCard(
          orchestratorId: 'orch-example-pending',
          requestingRrn: 'RRN-000000000099',
          fleetRrns: [robot.rrn, 'RRN-000000000099'],
          justification: 'Multi-robot coordination for warehouse automation',
          onGrant: () {},
          onDeny: () {},
        ),

        const SizedBox(height: 16),
        const Divider(),
        const SizedBox(height: 8),

        // Revocation info
        _InfoBanner(
          icon: Icons.security,
          color: Colors.blue,
          message: 'Any owner can revoke an orchestrator at any time. '
              'Active sessions are terminated within 60 seconds via RRF revocation polling.',
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Consent card for pending orchestrators
// ---------------------------------------------------------------------------

class _ConsentPendingCard extends StatelessWidget {
  final String orchestratorId;
  final String requestingRrn;
  final List<String> fleetRrns;
  final String justification;
  final VoidCallback onGrant;
  final VoidCallback onDeny;

  const _ConsentPendingCard({
    required this.orchestratorId,
    required this.requestingRrn,
    required this.fleetRrns,
    required this.justification,
    required this.onGrant,
    required this.onDeny,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.orange.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.orange.withOpacity(0.4)),
                  ),
                  child: const Text('PENDING CONSENT',
                      style: TextStyle(
                          fontSize: 10, color: Colors.orange, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Icon(Icons.smart_toy_outlined,
                    color: cs.primary, size: 20),
              ],
            ),
            const SizedBox(height: 12),
            _LabelValue(label: 'Orchestrator ID', value: orchestratorId),
            _LabelValue(label: 'Requesting RRN', value: requestingRrn),
            _LabelValue(label: 'Fleet RRNs', value: fleetRrns.join(', ')),
            _LabelValue(label: 'Justification', value: justification),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: onDeny,
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Deny'),
                    style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onGrant,
                    icon: const Icon(Icons.check, size: 16),
                    label: const Text('Grant Consent'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _LabelValue extends StatelessWidget {
  final String label;
  final String value;
  const _LabelValue({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: cs.onSurface.withOpacity(0.6),
                    fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(fontSize: 12, fontFamily: 'monospace')),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Register orchestrator dialog
// ---------------------------------------------------------------------------

class _RegisterOrchestratorDialog extends StatefulWidget {
  final String rrn;
  const _RegisterOrchestratorDialog({required this.rrn});

  @override
  State<_RegisterOrchestratorDialog> createState() =>
      _RegisterOrchestratorDialogState();
}

class _RegisterOrchestratorDialogState
    extends State<_RegisterOrchestratorDialog> {
  final _keyCtrl = TextEditingController();
  final _fleetCtrl = TextEditingController();
  final _justCtrl = TextEditingController();
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Register Orchestrator'),
      content: SizedBox(
        width: 480,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Register an M2M_TRUSTED orchestrator. All listed robot owners must '
              'consent before tokens are issued.',
              style: TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _keyCtrl,
              decoration: const InputDecoration(
                labelText: 'Orchestrator Ed25519 Public Key (PEM)',
                hintText: '-----BEGIN PUBLIC KEY-----\n...',
              ),
              maxLines: 4,
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _fleetCtrl,
              decoration: const InputDecoration(
                labelText: 'Fleet RRNs (comma-separated)',
                hintText: 'RRN-000000000001, RRN-000000000005',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _justCtrl,
              decoration: const InputDecoration(
                labelText: 'Justification',
                hintText: 'Purpose of multi-robot coordination',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _loading ? null : _register,
          child: _loading
              ? const SizedBox(
                  width: 16, height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Register'),
        ),
      ],
    );
  }

  Future<void> _register() async {
    setState(() => _loading = true);
    try {
      final fleetRrns = _fleetCtrl.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();

      final resp = await http.post(
        Uri.parse('$_rrfBaseUrl/v2/orchestrators/register'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'rrn':              widget.rrn,
          'orchestrator_key': _keyCtrl.text,
          'fleet_rrns':       fleetRrns,
          'justification':    _justCtrl.text,
        }),
      );

      if (mounted) {
        Navigator.pop(context);
        final success = resp.statusCode == 201;
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(success
              ? 'Orchestrator registered — awaiting consent from ${fleetRrns.length} owner(s)'
              : 'Registration failed: ${resp.body}'),
          backgroundColor: success ? Colors.green : Colors.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

// ---------------------------------------------------------------------------
// Info banner
// ---------------------------------------------------------------------------

class _InfoBanner extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String message;
  const _InfoBanner({
    required this.icon, required this.color, required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(message,
                style: TextStyle(fontSize: 12, color: color.withOpacity(0.9))),
          ),
        ],
      ),
    );
  }
}
