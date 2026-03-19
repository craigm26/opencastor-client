import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/mission.dart';
import 'create_mission_sheet.dart';

class MissionListScreen extends StatelessWidget {
  const MissionListScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return const Scaffold(body: Center(child: Text('Not signed in')));
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Missions'),
        centerTitle: false,
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _showCreateSheet(context),
        icon: const Icon(Icons.add),
        label: const Text('New Mission'),
      ),
      body: StreamBuilder<QuerySnapshot>(
        // participant_uids array-contains covers both owned + invited missions
        stream: FirebaseFirestore.instance
            .collection('missions')
            .where('participant_uids', arrayContains: uid)
            .orderBy('last_message_at', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(child: Text('Error: ${snapshot.error}'));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return _EmptyState(onNewMission: () => _showCreateSheet(context));
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 100),
            itemCount: docs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, i) {
              final mission = Mission.fromDocument(docs[i]);
              return _MissionCard(
                mission: mission,
                currentUid: uid,
                onTap: () => context.push('/missions/${mission.id}'),
              );
            },
          );
        },
      ),
    );
  }

  void _showCreateSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const CreateMissionSheet(),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _EmptyState extends StatelessWidget {
  final VoidCallback onNewMission;
  const _EmptyState({required this.onNewMission});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.track_changes_outlined,
              size: 64, color: cs.onSurfaceVariant.withOpacity(0.4)),
          const SizedBox(height: 16),
          Text('No missions yet',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 8),
          Text(
            'Start a multi-robot mission to coordinate\nyour fleet in a shared chat thread.',
            textAlign: TextAlign.center,
            style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: onNewMission,
            icon: const Icon(Icons.add),
            label: const Text('Create Mission'),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mission card
// ---------------------------------------------------------------------------

class _MissionCard extends StatelessWidget {
  final Mission mission;
  final String currentUid;
  final VoidCallback onTap;
  const _MissionCard({
    required this.mission,
    required this.currentUid,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final humanCount = mission.humanCount;
    final robotCount = mission.robotCount;
    final myRole = mission.roleOf(currentUid);
    final rolePart = myRole != null ? ' · ${myRole.label}' : '';

    // Summary line: "3 humans · 2 robots"
    final summary =
        '$humanCount human${humanCount != 1 ? "s" : ""} · $robotCount robot${robotCount != 1 ? "s" : ""}$rolePart';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isDark
              ? const Color(0xFF0ea5e9).withOpacity(0.15)
              : cs.outlineVariant,
        ),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Title row
              Row(
                children: [
                  const Icon(Icons.track_changes,
                      size: 18, color: Color(0xFF0ea5e9)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      mission.title,
                      style: Theme.of(context)
                          .textTheme
                          .titleSmall
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                  _StatusBadge(status: mission.status),
                ],
              ),
              const SizedBox(height: 6),

              // "N humans · M robots · My Role" summary
              Text(
                summary,
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),

              // Participant avatar row
              _ParticipantAvatarRow(
                participants: mission.participants,
                maxVisible: 6,
              ),
              const SizedBox(height: 8),

              // Time ago
              Text(
                _timeAgo(mission.lastMessageAt),
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inHours < 1) return '${diff.inMinutes}m ago';
    if (diff.inDays < 1) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ---------------------------------------------------------------------------
// Participant avatar row — small stacked icons
// ---------------------------------------------------------------------------

class _ParticipantAvatarRow extends StatelessWidget {
  final List<MissionParticipant> participants;
  final int maxVisible;
  const _ParticipantAvatarRow(
      {required this.participants, this.maxVisible = 6});

  @override
  Widget build(BuildContext context) {
    final visible = participants.take(maxVisible).toList();
    final overflow = participants.length - maxVisible;
    const size = 24.0;
    const overlap = 10.0;

    return SizedBox(
      height: size,
      child: Stack(
        children: [
          for (int i = 0; i < visible.length; i++)
            Positioned(
              left: i * (size - overlap),
              child: _MiniAvatar(
                  participant: visible[i], size: size),
            ),
          if (overflow > 0)
            Positioned(
              left: visible.length * (size - overlap),
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.outline,
                      width: 1),
                ),
                child: Center(
                  child: Text('+$overflow',
                      style: const TextStyle(fontSize: 9)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _MiniAvatar extends StatelessWidget {
  final MissionParticipant participant;
  final double size;
  const _MiniAvatar({required this.participant, this.size = 24});

  Color get _color {
    final id = participant.rrn ?? participant.uid ?? participant.name;
    const colors = [
      Color(0xFF0ea5e9),
      Color(0xFF8b5cf6),
      Color(0xFF22c55e),
      Color(0xFFf59e0b),
      Color(0xFFef4444),
      Color(0xFF06b6d4),
      Color(0xFFec4899),
    ];
    final hash = id.codeUnits.fold(0, (a, b) => a + b);
    return colors[hash % colors.length];
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: _color.withOpacity(0.2),
        shape: BoxShape.circle,
        border: Border.all(
            color: Theme.of(context).colorScheme.surface, width: 1.5),
      ),
      child: Icon(
        participant.isRobot
            ? Icons.smart_toy_outlined
            : Icons.person_outline,
        size: size * 0.55,
        color: _color,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Status badge
// ---------------------------------------------------------------------------

class _StatusBadge extends StatelessWidget {
  final MissionStatus status;
  const _StatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    String label;
    switch (status) {
      case MissionStatus.active:
        color = const Color(0xFF22c55e);
        label = 'Active';
      case MissionStatus.paused:
        color = const Color(0xFFf59e0b);
        label = 'Paused';
      case MissionStatus.completed:
        color = Colors.grey;
        label = 'Done';
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(label,
          style: TextStyle(
              fontSize: 11, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
