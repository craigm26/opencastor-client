/// Castor Credits card — balance, badge tier, redeem button (#21).
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'credits_redeem_sheet.dart';

// ── Model ──────────────────────────────────────────────────────────────────

class CreditsData {
  final int balance;
  final int redeemable;
  final String tier;
  final List<CreditLogEntry> recentLog;
  final DateTime? proUntil;

  const CreditsData({
    required this.balance,
    required this.redeemable,
    required this.tier,
    required this.recentLog,
    this.proUntil,
  });

  String get tierEmoji {
    switch (tier) {
      case 'silver':
        return '🥈';
      case 'gold':
        return '🥇';
      case 'diamond':
        return '💎';
      case 'champion':
        return '🏆';
      default:
        return '🥉';
    }
  }
}

class CreditLogEntry {
  final String description;
  final int amount;
  final DateTime? date;

  const CreditLogEntry({
    required this.description,
    required this.amount,
    this.date,
  });
}

// ── Provider ──────────────────────────────────────────────────────────────

final creditsProvider = FutureProvider.autoDispose<CreditsData>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) {
    return const CreditsData(
        balance: 0, redeemable: 0, tier: 'bronze', recentLog: []);
  }

  final snap = await FirebaseFirestore.instance
      .collection('robots')
      .where('firebase_uid', isEqualTo: uid)
      .limit(1)
      .get();

  if (snap.docs.isEmpty) {
    return const CreditsData(
        balance: 0, redeemable: 0, tier: 'bronze', recentLog: []);
  }

  final rrn = snap.docs.first.id;

  final callable = FirebaseFunctions.instance.httpsCallable(
    'robotApiGet',
    options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
  );

  final result = await callable.call(<String, dynamic>{
    'rrn': rrn,
    'path': '/api/credits',
  });

  final data = result.data;
  Map<String, dynamic> body;
  if (data is Map) {
    if (data['body'] is String) {
      final decoded = jsonDecode(data['body'] as String);
      body = decoded is Map
          ? Map<String, dynamic>.from(decoded)
          : <String, dynamic>{};
    } else if (data['body'] is Map) {
      body = Map<String, dynamic>.from(data['body'] as Map);
    } else {
      body = Map<String, dynamic>.from(data);
    }
  } else {
    return const CreditsData(
        balance: 0, redeemable: 0, tier: 'bronze', recentLog: []);
  }

  final log = <CreditLogEntry>[];
  final rawLog = body['log'];
  if (rawLog is List) {
    for (final entry in rawLog.take(3)) {
      if (entry is Map) {
        final m = Map<String, dynamic>.from(entry);
        DateTime? date;
        final rawDate = m['date'] ?? m['timestamp'];
        if (rawDate is String) date = DateTime.tryParse(rawDate);
        log.add(CreditLogEntry(
          description: m['description'] as String? ??
              m['type'] as String? ??
              '—',
          amount: (m['amount'] as num?)?.toInt() ?? 0,
          date: date,
        ));
      }
    }
  }

  DateTime? proUntil;
  final rawProUntil = body['pro_until'];
  if (rawProUntil is String && rawProUntil.isNotEmpty) {
    proUntil = DateTime.tryParse(rawProUntil);
  }

  return CreditsData(
    balance: (body['balance'] as num?)?.toInt() ?? 0,
    redeemable: (body['credits_redeemable'] as num?)?.toInt() ??
        (body['redeemable'] as num?)?.toInt() ??
        0,
    tier: body['tier'] as String? ?? 'bronze',
    recentLog: log,
    proUntil: proUntil,
  );
});

// ── Widget ─────────────────────────────────────────────────────────────────

class CreditsCard extends ConsumerWidget {
  const CreditsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final creditsAsync = ref.watch(creditsProvider);
    final theme = Theme.of(context);

    return creditsAsync.when(
      loading: () => const Card(
        child: Padding(
          padding: EdgeInsets.all(16),
          child: Center(child: CircularProgressIndicator()),
        ),
      ),
      error: (e, _) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(Icons.error_outline, color: theme.colorScheme.error),
              const SizedBox(width: 8),
              Expanded(
                child: Text('Credits unavailable',
                    style: theme.textTheme.bodyMedium),
              ),
              TextButton(
                onPressed: () => ref.invalidate(creditsProvider),
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      ),
      data: (credits) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '${credits.tierEmoji} Castor Credits',
                    style: theme.textTheme.titleMedium
                        ?.copyWith(fontWeight: FontWeight.w600),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.refresh, size: 18),
                    onPressed: () => ref.invalidate(creditsProvider),
                    tooltip: 'Refresh',
                    visualDensity: VisualDensity.compact,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '${credits.balance}',
                style: theme.textTheme.displaySmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: theme.colorScheme.primary,
                ),
              ),
              Text(
                '${credits.redeemable} redeemable',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
              if (credits.recentLog.isNotEmpty) ...[
                const SizedBox(height: 12),
                const Divider(height: 1),
                const SizedBox(height: 8),
                ...credits.recentLog.map((entry) => Padding(
                      padding: const EdgeInsets.symmetric(vertical: 2),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              entry.description,
                              style: theme.textTheme.bodySmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            entry.amount >= 0
                                ? '+${entry.amount}'
                                : '${entry.amount}',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: entry.amount >= 0
                                  ? Colors.green
                                  : theme.colorScheme.error,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    )),
              ],
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  icon: const Icon(Icons.redeem, size: 18),
                  label: const Text('Redeem Credits'),
                  onPressed: credits.redeemable > 0
                      ? () => showModalBottomSheet<void>(
                            context: context,
                            isScrollControlled: true,
                            builder: (_) =>
                                CreditsRedeemSheet(credits: credits),
                          )
                      : null,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
