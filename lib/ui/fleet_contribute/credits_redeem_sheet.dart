/// Credits Redeem bottom sheet (#21).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credits_card.dart';

// ── Redeem options ────────────────────────────────────────────────────────

class _RedeemOption {
  final String type;
  final String label;
  final String description;
  final int cost;
  final IconData icon;

  const _RedeemOption({
    required this.type,
    required this.label,
    required this.description,
    required this.cost,
    required this.icon,
  });
}

const _redeemOptions = [
  _RedeemOption(
    type: 'pro_month',
    label: 'Pro Month',
    description: 'One month of OpenCastor Pro',
    cost: 500,
    icon: Icons.workspace_premium,
  ),
  _RedeemOption(
    type: 'harness_run',
    label: 'Harness Run',
    description: 'One extra harness research run',
    cost: 200,
    icon: Icons.schema_outlined,
  ),
  _RedeemOption(
    type: 'api_boost',
    label: 'API Boost',
    description: '2× API rate limit for 7 days',
    cost: 150,
    icon: Icons.bolt_outlined,
  ),
  _RedeemOption(
    type: 'champion_badge',
    label: 'Champion Badge',
    description: 'Permanent 🏆 profile badge',
    cost: 250,
    icon: Icons.military_tech_outlined,
  ),
];

// ── Sheet ─────────────────────────────────────────────────────────────────

class CreditsRedeemSheet extends ConsumerStatefulWidget {
  final CreditsData credits;
  const CreditsRedeemSheet({super.key, required this.credits});

  @override
  ConsumerState<CreditsRedeemSheet> createState() =>
      _CreditsRedeemSheetState();
}

class _CreditsRedeemSheetState extends ConsumerState<CreditsRedeemSheet> {
  bool _redeeming = false;

  Future<void> _redeem(BuildContext context, _RedeemOption option) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Confirm Redemption'),
        content: Text(
            'Redeem ${option.cost} credits for "${option.label}"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Redeem'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _redeeming = true);
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) throw Exception('Not signed in');

      final snap = await FirebaseFirestore.instance
          .collection('robots')
          .where('firebase_uid', isEqualTo: uid)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) throw Exception('No robots found');
      final rrn = snap.docs.first.id;

      final callable = FirebaseFunctions.instance.httpsCallable(
        'robotApiGet',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 15)),
      );

      await callable.call(<String, dynamic>{
        'rrn': rrn,
        'path': '/api/credits/redeem',
        'method': 'POST',
        'body': {'type': option.type},
      });

      if (mounted) {
        ref.invalidate(creditsProvider);
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('${option.label} redeemed!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Redemption failed: $e'),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _redeeming = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final balance = widget.credits.redeemable;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text('Redeem Credits', style: theme.textTheme.titleLarge),
                const Spacer(),
                Text(
                  '$balance available',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            ..._redeemOptions.map((option) {
              final canAfford = balance >= option.cost;
              return ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  backgroundColor: canAfford
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                  child: Icon(
                    option.icon,
                    size: 20,
                    color: canAfford
                        ? theme.colorScheme.onPrimaryContainer
                        : theme.colorScheme.outline,
                  ),
                ),
                title: Text(
                  option.label,
                  style: TextStyle(
                    color: canAfford ? null : theme.colorScheme.outline,
                  ),
                ),
                subtitle: Text(
                  option.description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: canAfford
                        ? theme.colorScheme.onSurfaceVariant
                        : theme.colorScheme.outline,
                  ),
                ),
                trailing: _redeeming
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : FilledButton(
                        onPressed:
                            canAfford ? () => _redeem(context, option) : null,
                        child: Text('${option.cost}'),
                      ),
              );
            }),
          ],
        ),
      ),
    );
  }
}
