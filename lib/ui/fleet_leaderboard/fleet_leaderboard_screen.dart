/// Fleet Contribution Leaderboard Screen (#20).
///
/// Displays all robots grouped by hardware tier, sorted by contribution score
/// descending within each tier. Fetches data via the `robotApiGet` Cloud
/// Function at path `/api/contribute/leaderboard`.
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// ── Data model ────────────────────────────────────────────────────────────────

class _LeaderboardEntry {
  final String rrn;
  final double score;
  final int candidatesEvaluated;
  final DateTime? lastEval;
  final bool trusted;

  const _LeaderboardEntry({
    required this.rrn,
    required this.score,
    required this.candidatesEvaluated,
    required this.lastEval,
    required this.trusted,
  });

  factory _LeaderboardEntry.fromMap(Map<String, dynamic> m) {
    DateTime? lastEval;
    final rawEval = m['last_eval'];
    if (rawEval is String && rawEval.isNotEmpty) {
      lastEval = DateTime.tryParse(rawEval);
    }
    return _LeaderboardEntry(
      rrn: m['rrn'] as String? ?? '',
      score: (m['score'] as num?)?.toDouble() ?? 0.0,
      candidatesEvaluated:
          (m['candidates_evaluated'] as num?)?.toInt() ?? 0,
      lastEval: lastEval,
      trusted: m['trusted'] as bool? ?? true,
    );
  }
}

// ── Provider ──────────────────────────────────────────────────────────────────

/// Fetches the fleet leaderboard via `robotApiGet` at `/api/contribute/leaderboard`.
///
/// Uses the first robot the signed-in user owns to proxy the request.
/// Returns a map of hardware_tier → sorted list of entries (score descending).
final _leaderboardProvider =
    FutureProvider.autoDispose<Map<String, List<_LeaderboardEntry>>>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return {};

  // Resolve any robot RRN the user owns (needed by robotApiGet auth check).
  final snap = await FirebaseFirestore.instance
      .collection('robots')
      .where('firebase_uid', isEqualTo: uid)
      .limit(1)
      .get();

  if (snap.docs.isEmpty) return {};
  final rrn = snap.docs.first.id;

  final callable = FirebaseFunctions.instance.httpsCallable(
    'robotApiGet',
    options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
  );

  final result = await callable.call(<String, dynamic>{
    'rrn': rrn,
    'path': '/api/contribute/leaderboard',
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
    return {};
  }

  final tiers = <String, List<_LeaderboardEntry>>{};

  // Accept two shapes:
  //   (a) flat list at top-level or under "robots" key — group by hardware_tier
  //   (b) map of { hardware_tier: [ ... ] }
  List<dynamic>? flatList;
  if (body['robots'] is List) {
    flatList = body['robots'] as List;
  } else if (body.values.every((v) => v is! List)) {
    // No list values at all — return empty
  } else {
    // Check if all values are lists → treat as tier map
    final allLists = body.values.every((v) => v is List);
    if (allLists) {
      for (final tier in body.keys) {
        final entries = (body[tier] as List<dynamic>)
            .whereType<Map>()
            .map((m) => _LeaderboardEntry.fromMap(Map<String, dynamic>.from(m)))
            .toList();
        if (entries.isNotEmpty) tiers[tier] = entries;
      }
    } else {
      // Mixed — treat flat (might be the whole body as a list-like map)
      flatList = body.values.whereType<List>().expand((l) => l).toList();
    }
  }

  if (flatList != null) {
    for (final raw in flatList) {
      if (raw is! Map) continue;
      final m = Map<String, dynamic>.from(raw);
      final tier = m['hardware_tier'] as String? ?? 'unknown';
      tiers.putIfAbsent(tier, () => []).add(_LeaderboardEntry.fromMap(m));
    }
  }

  // Sort each tier by score descending
  for (final list in tiers.values) {
    list.sort((a, b) => b.score.compareTo(a.score));
  }

  return tiers;
});

// ── Screen ────────────────────────────────────────────────────────────────────

class FleetLeaderboardScreen extends ConsumerStatefulWidget {
  const FleetLeaderboardScreen({super.key});

  @override
  ConsumerState<FleetLeaderboardScreen> createState() =>
      _FleetLeaderboardScreenState();
}

class _FleetLeaderboardScreenState
    extends ConsumerState<FleetLeaderboardScreen> {
  @override
  Widget build(BuildContext context) {
    final tiersAsync = ref.watch(_leaderboardProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Fleet Leaderboard')),
      body: tiersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tiers) {
          if (tiers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.leaderboard_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text('No leaderboard data',
                      style: theme.textTheme.bodyLarge
                          ?.copyWith(color: theme.colorScheme.outline)),
                  const SizedBox(height: 4),
                  Text('Contribute compute to appear here.',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline)),
                ],
              ),
            );
          }

          return RefreshIndicator(
            onRefresh: () => ref.refresh(_leaderboardProvider.future),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                for (final tier in tiers.keys) ...[
                  _TierHeader(tier: tier),
                  ...tiers[tier]!.asMap().entries.map(
                        (e) => _EntryRow(
                          rank: e.key + 1,
                          entry: e.value,
                        ),
                      ),
                  const SizedBox(height: 8),
                ],
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Tier header ───────────────────────────────────────────────────────────────

class _TierHeader extends StatelessWidget {
  final String tier;
  const _TierHeader({required this.tier});

  static String _label(String t) => switch (t) {
        'pi5-hailo' => 'Pi 5 + Hailo-8 NPU',
        'pi5-8gb' => 'Pi 5 · 8 GB',
        'pi5-4gb' => 'Pi 5 · 4 GB',
        'pi4-8gb' => 'Pi 4 · 8 GB',
        'pi4-4gb' => 'Pi 4 · 4 GB',
        'server' => 'Server-class',
        'minimal' => 'Minimal',
        _ => t,
      };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Text(
        _label(tier),
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ── Entry row ─────────────────────────────────────────────────────────────────

class _EntryRow extends StatelessWidget {
  final int rank;
  final _LeaderboardEntry entry;

  const _EntryRow({required this.rank, required this.entry});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = entry.score.clamp(0.0, 1.0);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          // Rank
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: theme.textTheme.labelMedium
                  ?.copyWith(color: cs.onSurfaceVariant),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 12),

          // RRN + progress + meta
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        entry.rrn,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(fontFamily: 'monospace'),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!entry.trusted)
                      Padding(
                        padding: const EdgeInsets.only(left: 4),
                        child: Tooltip(
                          message: 'Untrusted',
                          child: Icon(Icons.warning_amber_rounded,
                              size: 16, color: theme.colorScheme.error),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 4),
                LinearProgressIndicator(
                  value: pct,
                  backgroundColor: cs.surfaceContainerHighest,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Text(
                      '${(pct * 100).toStringAsFixed(1)}%',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      '${_fmtCount(entry.candidatesEvaluated)} evaluated',
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    if (entry.lastEval != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(entry.lastEval!),
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _fmtCount(int n) {
    if (n < 1000) return '$n';
    if (n < 1000000) return '${(n / 1000).toStringAsFixed(1)}k';
    return '${(n / 1000000).toStringAsFixed(1)}M';
  }

  static String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')}';
  }
}
