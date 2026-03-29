/// MissionInviteBanner — shown on the Fleet screen when the user has a
/// pending mission invite.
///
/// Usage (in fleet_screen.dart or similar):
///   MissionInviteBanner()  // reads its own Firestore stream
///
/// Shows: 🎯 Craig invited you to "Kitchen Exploration"  [Join] [Decline]
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/mission.dart';

class MissionInviteBanner extends StatelessWidget {
  const MissionInviteBanner({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('mission_invites')
          .doc(uid)
          .collection('invites')
          .where('status', isEqualTo: 'pending')
          .orderBy('invited_at', descending: true)
          .limit(3) // show at most 3 banners stacked
          .snapshots(),
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final docs = snap.data!.docs;
        if (docs.isEmpty) return const SizedBox.shrink();

        return Column(
          children: docs.map((doc) {
            final invite = MissionInvite.fromDocument(doc);
            return _InviteBannerItem(invite: invite, uid: uid);
          }).toList(),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Single invite banner item
// ---------------------------------------------------------------------------

class _InviteBannerItem extends StatefulWidget {
  final MissionInvite invite;
  final String uid;
  const _InviteBannerItem({required this.invite, required this.uid});

  @override
  State<_InviteBannerItem> createState() => _InviteBannerItemState();
}

class _InviteBannerItemState extends State<_InviteBannerItem> {
  bool _busy = false;

  Future<void> _respond(bool accept) async {
    setState(() => _busy = true);
    try {
      final fn = FirebaseFunctions.instance.httpsCallable('joinMission');
      await fn.call({
        'missionId': widget.invite.missionId,
        'accept': accept,
      });
      if (accept && mounted) {
        context.push('/missions/${widget.invite.missionId}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final roleLabel = widget.invite.role.label;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF0c2340), const Color(0xFF122046)]
              : [const Color(0xFFe0f2fe), const Color(0xFFf0fdf4)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: const Color(0xFF0ea5e9).withValues(alpha: 0.3),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          const Text('🎯', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                RichText(
                  text: TextSpan(
                    style: TextStyle(
                        fontSize: 13,
                        color: cs.onSurface),
                    children: [
                      TextSpan(
                        text: widget.invite.invitedByName,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const TextSpan(text: ' invited you to '),
                      TextSpan(
                        text: '"${widget.invite.missionTitle}"',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'as $roleLabel',
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (_busy)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else ...[
            _ActionButton(
              label: 'Join',
              color: const Color(0xFF22c55e),
              onPressed: () => _respond(true),
            ),
            const SizedBox(width: 6),
            _ActionButton(
              label: 'Decline',
              color: cs.onSurfaceVariant,
              onPressed: () => _respond(false),
            ),
          ],
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;
  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Text(
          label,
          style: TextStyle(
              fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
