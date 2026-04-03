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

import 'fleet_leaderboard_view_model.dart';
import 'personal_research_card.dart';
import '../shared/pipeline_explainer.dart';
import '../shared/error_view.dart';
import '../shared/loading_view.dart';

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
        loading: () => const LoadingView(),
        error: (e, _) => ErrorView(error: e.toString()),
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
                // My Best Run — personal research card
                PersonalResearchCard(
                  communityChampionScore: championScore,
                ),
                const SizedBox(height: 8),
                // Active competition card (#25)
                const _CompetitionCard(),
                const SizedBox(height: 8),
                // Community Board header (#26)
                const _CommunityBoardHeader(),
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
                // Research Projects section (#32)
                const SizedBox(height: 4),
                const _ResearchProjectsHeader(),
                const SizedBox(height: 8),
                const _ResearchProjectsSection(),
                const SizedBox(height: 24),
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

// ── Competition Card (#25) ────────────────────────────────────────────────────

class _CompetitionCard extends StatelessWidget {
  const _CompetitionCard();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    // Placeholder top-3 data — will be replaced by live Firestore query
    const top3 = [
      ('RRN-000000000005', 0.934),
      ('RRN-000000000001', 0.912),
      ('RRN-000000000007', 0.887),
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: cs.surfaceContainer,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.emoji_events_outlined,
                      size: 18, color: cs.primary),
                  const SizedBox(width: 8),
                  Text(
                    'Season 1 — Sprint Series',
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: cs.primaryContainer,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      'ACTIVE',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: cs.onPrimaryContainer,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.8,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              ...top3.asMap().entries.map((e) {
                final rank = e.key + 1;
                final (rrn, score) = e.value;
                final medal =
                    rank == 1 ? '🥇' : rank == 2 ? '🥈' : '🥉';
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Text(medal,
                          style: const TextStyle(fontSize: 14)),
                      const SizedBox(width: 8),
                      Text(
                        rrn,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontFamily: 'monospace',
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        score.toStringAsFixed(3),
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: cs.primary,
                        ),
                      ),
                    ],
                  ),
                );
              }),
              const SizedBox(height: 8),
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    // TODO: navigate to full season standings
                  },
                  child: const Text('View All'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Community Board Header (#26) ──────────────────────────────────────────────

class _CommunityBoardHeader extends StatelessWidget {
  const _CommunityBoardHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(Icons.public_outlined, size: 16, color: cs.onSurfaceVariant),
          const SizedBox(width: 6),
          Text(
            'Community Board',
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

// ── Research Projects Section (#32) ──────────────────────────────────────────

class _ResearchProjectsHeader extends StatelessWidget {
  const _ResearchProjectsHeader();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        children: [
          Icon(Icons.science_outlined, size: 16, color: cs.primary),
          const SizedBox(width: 6),
          Text(
            'Research Projects',
            style: theme.textTheme.labelLarge?.copyWith(
              color: cs.primary,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.4,
            ),
          ),
          const Spacer(),
          Text(
            'Contribute compute · earn credits',
            style: theme.textTheme.labelSmall?.copyWith(
              color: cs.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

/// Static project definition — no network required for the list itself.
class _Project {
  final String id;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String description;
  final bool featured;

  const _Project({
    required this.id,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.description,
    this.featured = false,
  });
}

const _kProjects = [
  _Project(
    id: 'harness_research',
    icon: Icons.smart_toy_outlined,
    iconColor: Color(0xFF55d7ed),
    title: 'Harness Design Research',
    description:
        'Distributed search across ~263,424 AI agent harness configs — '
        'finding the optimal design for robotics tasks.',
    featured: true,
  ),
];

class _ResearchProjectsSection extends ConsumerWidget {
  const _ResearchProjectsSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final statusAsync = ref.watch(researchStatusProvider);
    final status = statusAsync.valueOrNull ?? {};
    return Column(
      children: [
        for (final project in _kProjects) ...[
          project.featured
              ? _FeaturedProjectCard(project: project, researchStatus: status)
              : _StandardProjectCard(project: project),
          const SizedBox(height: 8),
        ],
        // Coming soon placeholder
        _ComingSoonProjectsTile(),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ComingSoonProjectsTile extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerLowest,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: cs.outlineVariant.withValues(alpha: 0.3),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.more_horiz, size: 18, color: cs.onSurfaceVariant),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'More projects coming',
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: cs.onSurfaceVariant,
                      fontFamily: 'Space Grotesk',
                    ),
                  ),
                  Text(
                    'Climate modeling + protein folding — BOINC integrations planned Q3 2026',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.outline),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Featured card for Harness Design Research — elevated, amber chip, champion info.
class _FeaturedProjectCard extends StatefulWidget {
  final _Project project;
  final Map<String, dynamic> researchStatus;
  const _FeaturedProjectCard({
    required this.project,
    this.researchStatus = const {},
  });

  @override
  State<_FeaturedProjectCard> createState() => _FeaturedProjectCardState();
}

class _FeaturedProjectCardState extends State<_FeaturedProjectCard> {
  bool _contributing = true; // Bob is already contributing harness_research
  bool _loading = false;
  String? _errorMsg;

  Future<void> _toggle() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final fn = FirebaseFunctions.instance.httpsCallable(
        'activateCommunityProject',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      await fn.call(<String, dynamic>{
        'project_id': widget.project.id,
        'enabled': !_contributing,
      });
      if (mounted) setState(() => _contributing = !_contributing);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Could not update — try again');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const amber = Color(0xFFffba38);
    const cyan = Color(0xFF55d7ed);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainerHigh,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: cyan.withValues(alpha: 0.18),
            width: 1,
          ),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row — icon + title + FEATURED chip
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: cyan.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(widget.project.icon,
                      color: widget.project.iconColor, size: 20),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.project.title,
                    style: theme.textTheme.titleSmall?.copyWith(
                      fontFamily: 'Space Grotesk',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'FEATURED',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: amber,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              widget.project.description,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            // Pipeline explainer — community mode (this is the community card)
            const PipelineExplainer(mode: ContributeMode.community),
            const SizedBox(height: 10),
            // Search space progress bar
            _SearchProgressBar(status: widget.researchStatus),
            const SizedBox(height: 10),
            // Champion info row
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: cs.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  const Icon(Icons.emoji_events_outlined,
                      size: 14, color: amber),
                  const SizedBox(width: 6),
                  Text(
                    'Champion: ',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                  Text(
                    'lower_cost',
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: cyan,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    '·  0.9101',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Robot avatar row
            const Row(
              children: [
                _RobotBadge(name: 'Bob', contributing: true),
                SizedBox(width: 6),
                _RobotBadge(name: 'Alex', contributing: true),
                Spacer(),
              ],
            ),
            // Error message (inline, not snackbar)
            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: cs.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  children: [
                    Icon(Icons.warning_amber_outlined,
                        size: 14, color: cs.onErrorContainer),
                    const SizedBox(width: 6),
                    Text(
                      _errorMsg!,
                      style: theme.textTheme.labelSmall
                          ?.copyWith(color: cs.onErrorContainer),
                    ),
                  ],
                ),
              ),
            ],
            const SizedBox(height: 12),
            // CTA row
            Row(
              children: [
                Expanded(
                  child: _loading
                      ? const Center(
                          child: SizedBox(
                              height: 20,
                              width: 20,
                              child: CircularProgressIndicator(strokeWidth: 2)),
                        )
                      : FilledButton.icon(
                          icon: Icon(
                            _contributing
                                ? Icons.check_circle_outline
                                : Icons.volunteer_activism_outlined,
                            size: 16,
                          ),
                          label: Text(
                            _contributing ? 'Contributing ✓' : 'Contribute',
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: _contributing
                                ? const Color(0xFF4caf50).withValues(alpha: 0.85)
                                : cs.primary,
                            foregroundColor: Colors.white,
                            visualDensity: VisualDensity.compact,
                          ),
                          onPressed: _toggle,
                        ),
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  icon: const Icon(Icons.arrow_forward, size: 14),
                  label: const Text('View'),
                  style: OutlinedButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    side: BorderSide(color: cs.outline),
                  ),
                  onPressed: () {
                    // TODO: navigate to harness research detail
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SearchProgressBar extends StatelessWidget {
  final Map<String, dynamic> status;
  const _SearchProgressBar({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    const cyan = Color(0xFF55d7ed);
    const spaceSize = 263424;

    // Parse from API status — graceful fallback
    final totalEval = (status['total_runs'] as num?)?.toInt() ?? 0;
    final explored = totalEval;
    final pct = explored / spaceSize;
    final pctLabel = explored > 0
        ? '${(pct * 100).toStringAsFixed(2)}%'
        : '< 0.01%';

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                'Search space explored',
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              const Spacer(),
              Text(
                '${explored > 0 ? explored.toString() : "—"} / ${_fmt(spaceSize)}  $pctLabel',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: cyan,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: pct.clamp(0.0, 1.0),
              minHeight: 5,
              backgroundColor: cs.surfaceContainerLowest,
              valueColor: AlwaysStoppedAnimation<Color>(
                cyan.withValues(alpha: 0.8),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(int n) {
    // Simple thousands separator
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
  }
}

class _RobotBadge extends StatelessWidget {
  final String name;
  final bool contributing;
  const _RobotBadge({required this.name, required this.contributing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: contributing
            ? const Color(0xFF4caf50).withValues(alpha: 0.12)
            : cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: contributing
              ? const Color(0xFF4caf50).withValues(alpha: 0.4)
              : cs.outline.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            contributing ? Icons.check_circle : Icons.circle_outlined,
            size: 12,
            color: contributing
                ? const Color(0xFF4caf50)
                : cs.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            name,
            style: theme.textTheme.labelSmall?.copyWith(
              color: contributing
                  ? const Color(0xFF4caf50)
                  : cs.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

/// Standard project card for Climate Modeling, Protein Folding, etc.
class _StandardProjectCard extends StatefulWidget {
  final _Project project;
  const _StandardProjectCard({required this.project});

  @override
  State<_StandardProjectCard> createState() => _StandardProjectCardState();
}

class _StandardProjectCardState extends State<_StandardProjectCard> {
  bool _contributing = false;
  bool _loading = false;
  String? _errorMsg;

  Future<void> _toggle() async {
    setState(() {
      _loading = true;
      _errorMsg = null;
    });
    try {
      final fn = FirebaseFunctions.instance.httpsCallable(
        'activateCommunityProject',
        options: HttpsCallableOptions(timeout: const Duration(seconds: 10)),
      );
      await fn.call(<String, dynamic>{
        'project_id': widget.project.id,
        'enabled': !_contributing,
      });
      if (mounted) setState(() => _contributing = !_contributing);
    } catch (e) {
      if (mounted) {
        setState(() => _errorMsg = 'Could not activate — try again');
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(10),
        ),
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: widget.project.iconColor.withValues(alpha: 0.10),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Icon(widget.project.icon,
                      color: widget.project.iconColor, size: 18),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.project.title,
                        style: theme.textTheme.titleSmall?.copyWith(
                          fontFamily: 'Space Grotesk',
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        widget.project.description,
                        style: theme.textTheme.labelSmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (_errorMsg != null) ...[
              const SizedBox(height: 8),
              Text(
                _errorMsg!,
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: cs.error),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Text(
                  '0 robots',
                  style: theme.textTheme.labelSmall
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                const Spacer(),
                _loading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2))
                    : OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          side: BorderSide(
                            color: _contributing
                                ? const Color(0xFF4caf50)
                                : cs.primary,
                          ),
                          foregroundColor: _contributing
                              ? const Color(0xFF4caf50)
                              : cs.primary,
                        ),
                        onPressed: _toggle,
                        child: Text(
                          _contributing ? 'Contributing ✓' : 'Contribute',
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
