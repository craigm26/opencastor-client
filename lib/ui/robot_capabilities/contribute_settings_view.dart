/// Contribute settings: two distinct modes clearly explained.
///
/// Mode 1 — Donate Idle Compute:
///   When this robot is idle, it runs distributed harness research tasks
///   for the OpenCastor community. Earns Castor Credits and fleet rank.
///
/// Mode 2 — Auto-Apply Champions:
///   When the community verifies a new top-performing harness config,
///   automatically install it on this robot. Keeps the local harness
///   optimised without manual review.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/robot.dart';
import '../shared/loading_view.dart';

class ContributeSettingsView extends ConsumerStatefulWidget {
  final Robot robot;

  const ContributeSettingsView({super.key, required this.robot});

  @override
  ConsumerState<ContributeSettingsView> createState() =>
      _ContributeSettingsViewState();
}

class _ContributeSettingsViewState
    extends ConsumerState<ContributeSettingsView> {
  bool _donateEnabled = false;
  bool _autoApply = false;
  Map<String, dynamic>? _pendingChampion;
  bool _loading = true;
  bool _savingDonate = false;
  bool _savingAutoApply = false;
  bool _applying = false;
  String? _applyError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
  }

  Future<void> _loadSettings() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .get();
      if (!mounted) return;
      final data = doc.data();
      if (data != null) {
        final contribute = data['contribute'] as Map<String, dynamic>? ?? {};
        final pending = data['harness_pending'] as Map<String, dynamic>?;
        setState(() {
          _donateEnabled = contribute['enabled'] as bool? ?? false;
          _autoApply = contribute['auto_apply_champion'] as bool? ?? false;
          _pendingChampion = pending;
          _loading = false;
        });
      } else {
        setState(() => _loading = false);
      }
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _toggleDonate(bool v) async {
    setState(() => _savingDonate = true);
    try {
      // R2RAM command flow: write to robots/{rrn}/commands subcollection.
      // The bridge polls `.where("status", "==", "pending")` and executes
      // the instruction locally. Never write to the root robot doc for
      // operational state — the bridge owns that after execution.
      //
      // Instruction naming convention: <noun>_<verb> (no slash prefix).
      //   contribute_start → bridge enables idle-compute donation
      //   contribute_stop  → bridge disables idle-compute donation
      await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .collection('commands')
          .add({
        'instruction': v ? 'contribute_start' : 'contribute_stop',
        'scope': 'system',
        'source': 'app',
        'status': 'pending',
        'issued_at': FieldValue.serverTimestamp(),
      });

      if (mounted) setState(() => _donateEnabled = v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingDonate = false);
    }
  }

  Future<void> _toggleAutoApply(bool v) async {
    setState(() => _savingAutoApply = true);
    try {
      // R2RAM command flow: route through commands subcollection so the bridge
      // can validate and apply the change. Direct root-doc writes bypass the
      // authorization model and are silently ignored by the bridge.
      //
      //   contribute_auto_apply_on  → bridge enables auto-champion installs
      //   contribute_auto_apply_off → bridge disables auto-champion installs
      await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .collection('commands')
          .add({
        'instruction': v ? 'contribute_auto_apply_on' : 'contribute_auto_apply_off',
        'scope': 'system',
        'source': 'app',
        'status': 'pending',
        'issued_at': FieldValue.serverTimestamp(),
      });
      if (mounted) setState(() => _autoApply = v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _savingAutoApply = false);
    }
  }

  Future<void> _applyChampionNow() async {
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .collection('commands')
          .add({
        'instruction': '/harness apply-champion',
        'scope': 'system',
        'source': 'app',
        'status': 'pending',
        'created_at': FieldValue.serverTimestamp(),
        'issued_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _pendingChampion = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Champion config queued — robot will update on next cycle'),
            backgroundColor: Color(0xFF4caf50),
          ),
        );
      }
    } catch (e) {
      if (mounted) setState(() => _applyError = 'Could not apply — try again');
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    if (_loading) {
      return const LoadingView();
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Section header ────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.only(bottom: 12),
          child: Text(
            'Contribution modes',
            style: theme.textTheme.labelMedium?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
        ),

        // ── Mode 1: Donate idle compute ───────────────────────────────────
        _ModeCard(
          icon: Icons.volunteer_activism_outlined,
          title: 'Donate idle compute',
          description: _donateEnabled
              ? 'Running distributed tasks when idle — earning rank and Castor Credits'
              : 'When off, this robot keeps all compute for local tasks only',
          saving: _savingDonate,
          enabled: _donateEnabled,
          onChanged: _toggleDonate,
          accentColor: cs.primary,
        ),

        const SizedBox(height: 10),

        // ── Mode 2: Auto-apply champion configs ───────────────────────────
        _ModeCard(
          icon: Icons.auto_fix_high_outlined,
          title: 'Auto-apply champion configs',
          description: _autoApply
              ? 'Best harness configs from the community install automatically'
              : "New champion configs queue for your review before installing",
          saving: _savingAutoApply,
          enabled: _autoApply,
          onChanged: _toggleAutoApply,
          accentColor: const Color(0xFF55d7ed),
        ),

        // ── Pending champion banner ───────────────────────────────────────
        if (_pendingChampion != null) ...[
          const SizedBox(height: 10),
          _PendingChampionBanner(
            champion: _pendingChampion!,
            applying: _applying,
            applyError: _applyError,
            onApply: _applyChampionNow,
            onDismiss: () => setState(() => _pendingChampion = null),
          ),
        ],
      ],
    );
  }
}

// ── Reusable mode card ────────────────────────────────────────────────────────

class _ModeCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final bool saving;
  final bool enabled;
  final ValueChanged<bool> onChanged;
  final Color accentColor;

  const _ModeCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.saving,
    required this.enabled,
    required this.onChanged,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 12, 14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Icon(icon, size: 20, color: enabled ? accentColor : cs.onSurfaceVariant),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            saving
                ? const Padding(
                    padding: EdgeInsets.only(top: 4),
                    child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2)),
                  )
                : Switch.adaptive(
                    value: enabled,
                    activeColor: accentColor,
                    onChanged: onChanged,
                  ),
          ],
        ),
      ),
    );
  }
}

// ── Pending champion banner ───────────────────────────────────────────────────

class _PendingChampionBanner extends StatelessWidget {
  final Map<String, dynamic> champion;
  final bool applying;
  final String? applyError;
  final VoidCallback onApply;
  final VoidCallback onDismiss;

  const _PendingChampionBanner({
    required this.champion,
    required this.applying,
    required this.applyError,
    required this.onApply,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const amber = Color(0xFFffba38);

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: amber.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: amber.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.emoji_events_outlined, size: 16, color: amber),
              const SizedBox(width: 6),
              Text(
                'New champion config ready to install',
                style: theme.textTheme.labelMedium
                    ?.copyWith(color: amber, fontWeight: FontWeight.w600),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Candidate: ${champion['_candidate_id'] ?? '?'}  ·  '
            'Score: ${(champion['_score'] as num?)?.toStringAsFixed(4) ?? '?'}',
            style: theme.textTheme.bodySmall
                ?.copyWith(color: cs.onSurfaceVariant),
          ),
          if (applyError != null) ...[
            const SizedBox(height: 4),
            Text(applyError!,
                style:
                    theme.textTheme.labelSmall?.copyWith(color: cs.error)),
          ],
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: applying
                    ? const Center(
                        child: SizedBox(
                            height: 20,
                            width: 20,
                            child: CircularProgressIndicator(strokeWidth: 2)))
                    : FilledButton.icon(
                        icon: const Icon(Icons.check_circle_outline, size: 16),
                        label: const Text('Install on this robot'),
                        style: FilledButton.styleFrom(
                          backgroundColor: amber.withValues(alpha: 0.85),
                          foregroundColor: Colors.black87,
                          visualDensity: VisualDensity.compact,
                        ),
                        onPressed: onApply,
                      ),
              ),
              const SizedBox(width: 8),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  visualDensity: VisualDensity.compact,
                  side: BorderSide(color: cs.outline.withValues(alpha: 0.5)),
                ),
                onPressed: onDismiss,
                child: const Text('Dismiss'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
