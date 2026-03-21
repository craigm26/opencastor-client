/// OpenCastor Pro waitlist screen (#22).
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../fleet_contribute/credits_card.dart';

class ProScreen extends ConsumerWidget {
  const ProScreen({super.key});

  static const _features = [
    'Private fleet leaderboard',
    '2× API rate limits',
    'Managed harness research scheduling',
    'Extended contribute history (1 year)',
    'Email support SLA (48h)',
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditsAsync = ref.watch(creditsProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('OpenCastor Pro')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Pro active banner
          creditsAsync.maybeWhen(
            data: (credits) {
              final proUntil = credits.proUntil;
              if (proUntil != null && proUntil.isAfter(DateTime.now())) {
                return Column(
                  children: [
                    Card(
                      color: Colors.green.withValues(alpha: 0.12),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            const Icon(Icons.check_circle,
                                color: Colors.green),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'Pro Active until '
                                '${DateFormat.yMMMd().format(proUntil)}',
                                style: theme.textTheme.bodyLarge?.copyWith(
                                  color: Colors.green,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                );
              }
              return const SizedBox.shrink();
            },
            orElse: () => const SizedBox.shrink(),
          ),

          // Price display
          Card(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '\$19/month',
                    style: theme.textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: theme.colorScheme.primary,
                    ),
                  ),
                  Text(
                    '(launching soon)',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Feature list
          Card(
            child: Column(
              children: _features
                  .map((f) => ListTile(
                        leading: Icon(Icons.check_circle_outline,
                            color: theme.colorScheme.primary),
                        title: Text(f),
                      ))
                  .toList(),
            ),
          ),

          const SizedBox(height: 24),

          // CTAs
          creditsAsync.maybeWhen(
            data: (credits) {
              final proUntil = credits.proUntil;
              if (proUntil != null && proUntil.isAfter(DateTime.now())) {
                return const SizedBox.shrink();
              }
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _WaitlistButton(),
                  if (credits.redeemable >= 500) ...[
                    const SizedBox(height: 12),
                    _RedeemProButton(credits: credits),
                  ],
                ],
              );
            },
            orElse: () => const Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [_WaitlistButton()],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Waitlist button ────────────────────────────────────────────────────────

class _WaitlistButton extends StatefulWidget {
  const _WaitlistButton();

  @override
  State<_WaitlistButton> createState() => _WaitlistButtonState();
}

class _WaitlistButtonState extends State<_WaitlistButton> {
  void _showDialog() {
    final emailController = TextEditingController();
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Join Waitlist'),
        content: TextField(
          controller: emailController,
          keyboardType: TextInputType.emailAddress,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Email address',
            hintText: 'you@example.com',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("You're on the list!"),
                  duration: Duration(seconds: 3),
                ),
              );
            },
            child: const Text('Submit'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FilledButton.icon(
      icon: const Icon(Icons.mail_outline),
      label: const Text('Join Waitlist'),
      onPressed: _showDialog,
    );
  }
}

// ── Redeem Pro button ──────────────────────────────────────────────────────

class _RedeemProButton extends ConsumerStatefulWidget {
  final CreditsData credits;
  const _RedeemProButton({required this.credits});

  @override
  ConsumerState<_RedeemProButton> createState() => _RedeemProButtonState();
}

class _RedeemProButtonState extends ConsumerState<_RedeemProButton> {
  bool _loading = false;

  Future<void> _redeem() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Redeem Pro Month'),
        content: const Text(
            'Use 500 credits for one month of OpenCastor Pro?'),
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

    setState(() => _loading = true);
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
        'body': {'type': 'pro_month'},
      });

      if (mounted) {
        ref.invalidate(creditsProvider);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Pro Month activated!'),
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
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      icon: _loading
          ? const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : const Icon(Icons.redeem),
      label: const Text('Redeem 500 Credits'),
      onPressed: _loading ? null : _redeem,
    );
  }
}
