/// Pending Consent Screen — RCAN v1.5 GAP-05 (Consent Wire Protocol)
///
/// Shows incoming consent requests where the authenticated user is the
/// target robot's owner. The user can approve or deny each request.
///
/// Data source: Firestore `/consent_requests` where
///   `target_owner_uid == currentUser.uid`  (filtered by [ConsentRepository]).
///
/// Approve → calls `resolveConsent` Cloud Function via [ConsentRepository.approve]
/// Deny    → calls `resolveConsent` with deny via [ConsentRepository.deny]
///
/// MVVM: all Firestore/Cloud Function calls go through [ConsentRepository].
/// This screen only calls methods and reads state — never talks to Firestore directly.
library;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../data/models/robot.dart';
import '../../data/repositories/consent_repository.dart';
import '../../data/repositories/consent_repository_provider.dart';
import '../../data/repositories/robot_repository.dart';
import '../../ui/core/theme/app_theme.dart';
import '../fleet/fleet_view_model.dart' show robotRepositoryProvider;
import '../shared/loading_view.dart';

// ── Providers ─────────────────────────────────────────────────────────────────

// Use the global wired-up provider
final _consentRepositoryProvider = consentRepositoryProvider;

/// All pending consent requests across all robots owned by the current user.
final pendingConsentProvider =
    StreamProvider<List<_PendingItem>>((ref) async* {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  if (uid.isEmpty) {
    yield [];
    return;
  }

  final repo = ref.read(robotRepositoryProvider);
  final consentRepo = ref.read(_consentRepositoryProvider);

  // Get user's robots
  final robots = await repo.watchFleet(uid).first;

  if (robots.isEmpty) {
    yield [];
    return;
  }

  // For each robot, watch pending requests and merge into flat list
  final streams = robots.map((robot) => consentRepo
      .watchPendingRequests(robot.rrn)
      .map((reqs) =>
          reqs.map((req) => _PendingItem(robot: robot, request: req)).toList()));

  // Merge all streams into one flat list
  await for (final _ in streams.first) {
    final allItems = <_PendingItem>[];
    for (final robot in robots) {
      final reqs = await consentRepo.watchPendingRequests(robot.rrn).first;
      allItems.addAll(
          reqs.map((req) => _PendingItem(robot: robot, request: req)));
    }
    allItems.sort((a, b) =>
        b.request.createdAt.compareTo(a.request.createdAt));
    yield allItems;
  }
});

// ── Data classes ──────────────────────────────────────────────────────────────

class _PendingItem {
  final Robot robot;
  final ConsentRequest request;
  const _PendingItem({required this.robot, required this.request});
}

// ── Screen ────────────────────────────────────────────────────────────────────

class PendingConsentScreen extends ConsumerWidget {
  const PendingConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(pendingConsentProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pending Consent Requests'),
      ),
      body: pendingAsync.when(
        loading: () => const LoadingView(),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline, size: 48),
                const SizedBox(height: 16),
                Text('Error loading consent requests',
                    style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(e.toString(),
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center),
              ],
            ),
          ),
        ),
        data: (items) {
          if (items.isEmpty) {
            return _EmptyState();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(pendingConsentProvider),
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (ctx, i) =>
                  _PendingConsentCard(item: items[i]),
            ),
          );
        },
      ),
    );
  }
}

// ── Pending consent card ──────────────────────────────────────────────────────

class _PendingConsentCard extends ConsumerWidget {
  final _PendingItem item;
  const _PendingConsentCard({required this.item});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final req = item.request;
    final robot = item.robot;
    final cs = Theme.of(context).colorScheme;
    final repo = ref.read(_consentRepositoryProvider);

    // GAP-08: detect service sender (shows ⚠️ Service banner)
    final isServiceRequest =
        req.fromOwner.startsWith('service:') ||
        req.fromRuri.contains('/service/');

    return Card(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: isServiceRequest
              ? Colors.amber.withValues(alpha: 0.4)
              : AppTheme.warning.withValues(alpha: 0.25),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ─────────────────────────────────────────────────
            Row(
              children: [
                Icon(
                  isServiceRequest
                      ? Icons.computer_outlined
                      : Icons.handshake_outlined,
                  size: 16,
                  color: isServiceRequest
                      ? Colors.amber
                      : AppTheme.warning,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        req.fromOwner,
                        style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      Text(
                        'wants access to ${robot.name}',
                        style: TextStyle(
                            fontSize: 12,
                            color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Text(
                  timeago.format(req.createdAt),
                  style: TextStyle(
                      fontSize: 11, color: cs.onSurfaceVariant),
                ),
              ],
            ),

            // ── GAP-08 Service banner ──────────────────────────────────
            if (isServiceRequest) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.amber.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: Colors.amber.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.warning_amber_outlined,
                        size: 14, color: Colors.amber),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        '⚠️ Service Request: ${req.fromOwner}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.amber,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 10),

            // ── Reason ─────────────────────────────────────────────────
            if (req.reason.isNotEmpty) ...[
              Text(
                req.reason,
                style: TextStyle(
                    fontSize: 12, color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 8),
            ],

            // ── Requested scopes ───────────────────────────────────────
            Wrap(
              spacing: 6,
              runSpacing: 4,
              children: req.requestedScopes
                  .map((s) => _ScopeChip(scope: s))
                  .toList(),
            ),
            const SizedBox(height: 8),

            // ── Duration ───────────────────────────────────────────────
            Row(
              children: [
                Icon(Icons.timer_outlined,
                    size: 12, color: cs.onSurfaceVariant),
                const SizedBox(width: 4),
                Text(
                  req.durationHours == 0
                      ? 'Permanent access'
                      : 'For ${_formatDuration(req.durationHours)}',
                  style: TextStyle(
                      fontSize: 12, color: cs.onSurfaceVariant),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // ── From RRN ───────────────────────────────────────────────
            if (req.fromRrn.isNotEmpty) ...[
              Row(
                children: [
                  Icon(Icons.tag_outlined,
                      size: 12, color: cs.onSurfaceVariant),
                  const SizedBox(width: 4),
                  Text(
                    req.fromRrn,
                    style: TextStyle(
                        fontSize: 11,
                        color: cs.onSurfaceVariant,
                        fontFamily: 'monospace'),
                  ),
                ],
              ),
              const SizedBox(height: 14),
            ],

            // ── Actions ────────────────────────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                OutlinedButton.icon(
                  onPressed: () =>
                      _deny(context, repo, robot.rrn, req.id),
                  icon: const Icon(Icons.close, size: 14),
                  label: const Text('Deny'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.danger,
                    side: BorderSide(
                        color: AppTheme.danger.withValues(alpha: 0.5)),
                  ),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: () => _approve(
                      context, repo, robot.rrn, req),
                  icon: const Icon(Icons.check, size: 14),
                  label: const Text('Approve'),
                  style: FilledButton.styleFrom(
                      backgroundColor: AppTheme.online),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(
    BuildContext ctx,
    ConsentRepository repo,
    String rrn,
    ConsentRequest req,
  ) async {
    try {
      await repo.approve(
        rrn: rrn,
        requestId: req.id,
        grantedScopes: req.requestedScopes,
        durationHours: req.durationHours,
      );
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Access granted to ${req.fromOwner}'),
            backgroundColor: AppTheme.online,
          ),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  Future<void> _deny(
    BuildContext ctx,
    ConsentRepository repo,
    String rrn,
    String requestId,
  ) async {
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (_) => AlertDialog(
        title: const Text('Deny request?'),
        content: const Text(
            'The requester will be notified that access was denied.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('Cancel')),
          FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.danger),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Deny')),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await repo.deny(rrn: rrn, requestId: requestId);
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          const SnackBar(content: Text('Request denied')),
        );
      }
    } catch (e) {
      if (ctx.mounted) {
        ScaffoldMessenger.of(ctx).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: AppTheme.danger,
          ),
        );
      }
    }
  }

  String _formatDuration(int hours) {
    if (hours < 24) return '$hours hour${hours == 1 ? '' : 's'}';
    final days = hours ~/ 24;
    return '$days day${days == 1 ? '' : 's'}';
  }
}

// ── Empty state ───────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.check_circle_outline,
            size: 64,
            color: AppTheme.online,
          ),
          const SizedBox(height: 16),
          Text(
            'No pending requests',
            style: Theme.of(context).textTheme.titleLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Incoming consent requests from other robot owners\nwill appear here.',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}

// ── Scope chip ────────────────────────────────────────────────────────────────

class _ScopeChip extends StatelessWidget {
  final String scope;
  const _ScopeChip({required this.scope});

  static const _colors = {
    'control': Colors.red,
    'safety': Colors.deepOrange,
    'chat': Colors.blue,
    'status': Colors.teal,
    'discover': Colors.grey,
    'transparency': Colors.purple,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[scope] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        scope,
        style: TextStyle(
            fontSize: 10, color: color, fontWeight: FontWeight.w600),
      ),
    );
  }
}
