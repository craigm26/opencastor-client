/// Contribute settings: enable/disable toggle, auto-apply champion toggle,
/// and manual "Apply Champion Now" action.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/models/robot.dart';

class ContributeSettingsView extends ConsumerStatefulWidget {
  final Robot robot;

  const ContributeSettingsView({super.key, required this.robot});

  @override
  ConsumerState<ContributeSettingsView> createState() =>
      _ContributeSettingsViewState();
}

class _ContributeSettingsViewState
    extends ConsumerState<ContributeSettingsView> {
  bool _enabled = false;
  bool _autoApply = false;
  Map<String, dynamic>? _pendingChampion;
  bool _loading = true;
  bool _saving = false;
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
          _enabled = contribute['enabled'] as bool? ?? false;
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

  Future<void> _toggleEnabled(bool v) async {
    setState(() => _saving = true);
    try {
      final db = FirebaseFirestore.instance;
      final rrn = widget.robot.rrn;

      // Write command to Firestore commands subcollection.
      // The bridge polls this and executes /contribute start|stop locally.
      // (sendRobotCommand CF is not used — local robots need direct Firestore writes.)
      await db
          .collection('robots')
          .doc(rrn)
          .collection('commands')
          .add({
        'instruction': v ? '/contribute start' : '/contribute stop',
        'scope': 'system',
        'source': 'app',
        'created_at': FieldValue.serverTimestamp(),
      });

      // Also update contribute toggle state directly so UI is always consistent.
      await db
          .collection('robots')
          .doc(rrn)
          .set({'contribute': {'enabled': v}}, SetOptions(merge: true));

      if (mounted) setState(() => _enabled = v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: \$e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _toggleAutoApply(bool v) async {
    setState(() => _saving = true);
    try {
      await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .set({
        'contribute': {'auto_apply_champion': v}
      }, SetOptions(merge: true));
      if (mounted) setState(() => _autoApply = v);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error saving auto-apply setting: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _applyChampionNow() async {
    setState(() {
      _applying = true;
      _applyError = null;
    });
    try {
      // Write apply-champion command to Firestore — bridge executes locally.
      await FirebaseFirestore.instance
          .collection('robots')
          .doc(widget.robot.rrn)
          .collection('commands')
          .add({
        'instruction': '/harness apply-champion',
        'scope': 'system',
        'source': 'app',
        'created_at': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _pendingChampion = null);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Apply-champion command sent — robot will update on next cycle'),
            backgroundColor: Color(0xFF4caf50),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _applyError = 'Could not apply — try again');
      }
    } finally {
      if (mounted) setState(() => _applying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const cyan = Color(0xFF55d7ed);
    const amber = Color(0xFFffba38);

    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return Card(
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Enable/disable toggle ────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.science_outlined, size: 20, color: cs.primary),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Compute Contribution',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
                if (_saving)
                  const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2))
                else
                  Switch.adaptive(
                    value: _enabled,
                    onChanged: _toggleEnabled,
                  ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              _enabled
                  ? 'Contributing when idle — earning rank and Castor Credits'
                  : 'Enable to earn rank and Castor Credits from idle compute',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),

            if (_enabled) ...[
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 12),

              // ── Pending champion banner ────────────────────────────────────
              if (_pendingChampion != null) ...[
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                        color: amber.withValues(alpha: 0.3), width: 1),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(Icons.emoji_events_outlined,
                              size: 16, color: amber),
                          const SizedBox(width: 6),
                          Text(
                            'New champion config available',
                            style: theme.textTheme.labelMedium?.copyWith(
                              color: amber,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Candidate: ${_pendingChampion!['_candidate_id'] ?? '?'}  '
                        '·  Score: ${(_pendingChampion!['_score'] as num?)?.toStringAsFixed(4) ?? '?'}',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (_applyError != null) ...[
                        const SizedBox(height: 6),
                        Text(_applyError!,
                            style: theme.textTheme.labelSmall
                                ?.copyWith(color: cs.error)),
                      ],
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _applying
                                ? const Center(
                                    child: SizedBox(
                                        height: 20,
                                        width: 20,
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2)))
                                : FilledButton.icon(
                                    icon: const Icon(
                                        Icons.check_circle_outline,
                                        size: 16),
                                    label: const Text('Apply to this robot'),
                                    style: FilledButton.styleFrom(
                                      backgroundColor:
                                          amber.withValues(alpha: 0.85),
                                      foregroundColor: Colors.black87,
                                      visualDensity: VisualDensity.compact,
                                    ),
                                    onPressed: _applyChampionNow,
                                  ),
                          ),
                          const SizedBox(width: 8),
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                              side: BorderSide(
                                  color:
                                      cs.outline.withValues(alpha: 0.5)),
                            ),
                            onPressed: () =>
                                setState(() => _pendingChampion = null),
                            child: const Text('Dismiss'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
              ],

              // ── Auto-apply toggle ──────────────────────────────────────────
              Row(
                children: [
                  Icon(Icons.update_outlined, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Auto-apply champion configs',
                          style: theme.textTheme.bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w500),
                        ),
                        Text(
                          _autoApply
                              ? 'New champion configs apply automatically'
                              : 'You review and apply champion configs manually',
                          style: theme.textTheme.bodySmall
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Switch.adaptive(
                    value: _autoApply,
                    activeThumbColor: cyan,
                    onChanged: _toggleAutoApply,
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}
