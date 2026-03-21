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

import 'personal_research_card.dart';

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
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _searchController.addListener(() {
      setState(() {
        _searchQuery = _searchController.text.toLowerCase();
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tiersAsync = ref.watch(_leaderboardProvider);
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          'Fleet Leaderboard',
          style: theme.textTheme.titleLarge?.copyWith(
            fontFamily: 'Space Grotesk',
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: _SearchBar(controller: _searchController),
          ),
        ),
      ),
      body: tiersAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (tiers) {
          // Filter tiers and entries based on search
          final filteredTiers = <String, List<_LeaderboardEntry>>{};
          for (final entry in tiers.entries) {
            final tierNameMatch = entry.key.toLowerCase().contains(_searchQuery);
            final matchingEntries = entry.value.where((robot) {
              return tierNameMatch || robot.rrn.toLowerCase().contains(_searchQuery);
            }).toList();

            if (matchingEntries.isNotEmpty) {
              filteredTiers[entry.key] = matchingEntries;
            }
          }

          if (filteredTiers.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.leaderboard_outlined,
                      size: 48, color: theme.colorScheme.outline),
                  const SizedBox(height: 12),
                  Text(
                    _searchQuery.isNotEmpty 
                        ? 'No robots match "$_searchQuery"'
                        : 'No leaderboard data',
                    style: theme.textTheme.bodyLarge
                        ?.copyWith(color: theme.colorScheme.outline),
                  ),
                  if (_searchQuery.isEmpty) ...[
                    const SizedBox(height: 4),
                    Text('Contribute compute to appear here.',
                        style: theme.textTheme.bodySmall
                            ?.copyWith(color: theme.colorScheme.outline)),
                  ]
                ],
              ),
            );
          }

          // Champion score = highest score across all tiers
          final championScore = tiers.values
              .expand((list) => list)
              .fold<double>(0.0, (max, e) => e.score > max ? e.score : max);

          return RefreshIndicator(
            onRefresh: () => ref.refresh(_leaderboardProvider.future),
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 8),
              children: [
                // Personal research card — always at top of leaderboard
                PersonalResearchCard(
                  communityChampionScore: championScore,
                ),
                for (final tier in filteredTiers.keys) ...[
                  _TierHeader(tier: tier),
                  ...filteredTiers[tier]!.asMap().entries.map(
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

// ── Search Bar ────────────────────────────────────────────────────────────────

class _SearchBar extends StatefulWidget {
  final TextEditingController controller;

  const _SearchBar({required this.controller});

  @override
  State<_SearchBar> createState() => _SearchBarState();
}

class _SearchBarState extends State<_SearchBar> {
  final FocusNode _focusNode = FocusNode();
  bool _isFocused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() {
        _isFocused = _focusNode.hasFocus;
      });
    });
  }

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        border: Border(
          bottom: BorderSide(
            color: _isFocused ? cs.primary : cs.outline,
            width: 2.0,
          ),
        ),
      ),
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        style: theme.textTheme.bodyMedium?.copyWith(fontFamily: 'Inter'),
        decoration: InputDecoration(
          hintText: 'Search robots or tiers...',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            color: cs.onSurfaceVariant,
            fontFamily: 'Inter',
          ),
          prefixIcon: Icon(
            Icons.search,
            color: _isFocused ? cs.primary : cs.onSurfaceVariant,
          ),
          border: InputBorder.none,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        ),
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
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        _label(tier),
        style: theme.textTheme.headlineSmall?.copyWith(
          color: theme.colorScheme.primary,
          letterSpacing: 0.5,
          fontFamily: 'Space Grotesk',
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

  Widget _buildBadge(double score) {
    Color bgColor;
    Color fgColor;
    String label;

    if (score > 0.9) {
      // Diamond
      bgColor = const Color(0xFFb9f2ff); // Light cyan
      fgColor = const Color(0xFF004d57);
      label = 'DIAMOND';
    } else if (score > 0.75) {
      // Gold
      bgColor = const Color(0xFFffdf99); // Light amber
      fgColor = const Color(0xFF5d3f00);
      label = 'GOLD';
    } else if (score > 0.5) {
      // Silver
      bgColor = const Color(0xFFe3e2e6); // Light greyish
      fgColor = const Color(0xFF44474f);
      label = 'SILVER';
    } else {
      // Bronze
      bgColor = const Color(0xFFffb4a1); // Light deep orange/bronze
      fgColor = const Color(0xFF631000);
      label = 'BRONZE';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: fgColor,
          fontSize: 10,
          fontWeight: FontWeight.bold,
          fontFamily: 'Inter',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final pct = entry.score.clamp(0.0, 1.0);

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: cs.surfaceContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          // Rank & Badge column
          SizedBox(
            width: 60,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  '#$rank',
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontFamily: 'Space Grotesk',
                  ),
                ),
                const SizedBox(height: 6),
                _buildBadge(pct),
              ],
            ),
          ),
          const SizedBox(width: 16),

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
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontFamily: 'Inter',
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (!entry.trusted)
                      Container(
                        margin: const EdgeInsets.only(left: 8),
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: cs.errorContainer,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.warning_amber_rounded,
                                size: 12, color: cs.onErrorContainer),
                            const SizedBox(width: 4),
                            Text(
                              'UNTRUSTED',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onErrorContainer,
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Inter',
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(
                  value: pct,
                  backgroundColor: cs.surfaceContainerHighest,
                  minHeight: 4,
                  borderRadius: BorderRadius.circular(2),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      '${_fmtCount(entry.candidatesEvaluated)} eval',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                        fontFamily: 'Inter',
                      ),
                    ),
                    if (entry.lastEval != null) ...[
                      const SizedBox(width: 8),
                      Text(
                        '•',
                        style: TextStyle(color: cs.onSurfaceVariant, fontSize: 10),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(entry.lastEval!),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: cs.onSurfaceVariant,
                          fontFamily: 'Inter',
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 16),
          // Score
          Text(
            pct.toStringAsFixed(2),
            style: theme.textTheme.headlineMedium?.copyWith(
              fontFamily: 'Space Grotesk',
              color: cs.primary,
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
