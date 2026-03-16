import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:timeago/timeago.dart' as timeago;
import '../../models/consent_request.dart';
import '../../models/robot.dart';
import '../../services/consent_service.dart';
import '../../services/robot_service.dart';
import '../../theme/app_theme.dart';

final _consentSvcProvider = Provider((_) => ConsentService());
final _robotSvcProvider = Provider((_) => RobotService());

final _fleetProvider = StreamProvider<List<Robot>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
  return ref.read(_robotSvcProvider).watchFleet(uid);
});

final _pendingRequestsProvider =
    StreamProvider.family<List<ConsentRequest>, String>((ref, rrn) {
  return ref.read(_consentSvcProvider).watchPendingRequests(rrn);
});

final _peersProvider =
    StreamProvider.family<List<Map<String, dynamic>>, String>((ref, rrn) {
  return ref.read(_consentSvcProvider).watchPeers(rrn);
});

class ConsentScreen extends ConsumerWidget {
  const ConsentScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleetAsync = ref.watch(_fleetProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Access & Consent')),
      body: fleetAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('Error: $e')),
        data: (robots) {
          if (robots.isEmpty) {
            return const Center(child: Text('No robots in your fleet.'));
          }
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              for (final robot in robots) ...[
                _RobotConsentSection(robot: robot),
                const SizedBox(height: 16),
              ],
            ],
          );
        },
      ),
    );
  }
}

class _RobotConsentSection extends ConsumerWidget {
  final Robot robot;
  const _RobotConsentSection({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pendingAsync = ref.watch(_pendingRequestsProvider(robot.rrn));
    final peersAsync = ref.watch(_peersProvider(robot.rrn));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Robot header
        Row(
          children: [
            const Icon(Icons.precision_manufacturing_outlined, size: 16),
            const SizedBox(width: 8),
            Text(robot.name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.bold)),
            const Spacer(),
            Text(robot.rrn,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant)),
          ],
        ),
        const SizedBox(height: 8),

        // Pending requests
        pendingAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (requests) {
            if (requests.isEmpty) return const SizedBox.shrink();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(
                    label: 'Pending requests (${requests.length})',
                    color: AppTheme.warning),
                const SizedBox(height: 6),
                for (final req in requests)
                  _ConsentRequestCard(robot: robot, request: req),
                const SizedBox(height: 12),
              ],
            );
          },
        ),

        // Established peers
        peersAsync.when(
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
          data: (peers) {
            if (peers.isEmpty) {
              return Padding(
                padding: const EdgeInsets.only(left: 4, bottom: 4),
                child: Text('No active peer consents.',
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _SectionLabel(label: 'Active peers', color: AppTheme.online),
                const SizedBox(height: 6),
                for (final peer in peers)
                  _PeerTile(robot: robot, peer: peer),
              ],
            );
          },
        ),
        const Divider(),
      ],
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String label;
  final Color color;
  const _SectionLabel({required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
            width: 3, height: 14,
            decoration: BoxDecoration(
                color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                fontSize: 12, fontWeight: FontWeight.w600, color: color)),
      ],
    );
  }
}

class _ConsentRequestCard extends ConsumerWidget {
  final Robot robot;
  final ConsentRequest request;
  const _ConsentRequestCard({required this.robot, required this.request});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(_consentSvcProvider);
    final cs = Theme.of(context).colorScheme;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      color: AppTheme.warning.withOpacity(0.05),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: AppTheme.warning.withOpacity(0.3)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.handshake_outlined, size: 14, color: AppTheme.warning),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(request.fromOwner,
                      style: const TextStyle(
                          fontWeight: FontWeight.bold, fontSize: 13)),
                ),
                Text(timeago.format(request.createdAt),
                    style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
              ],
            ),
            const SizedBox(height: 6),
            if (request.reason.isNotEmpty)
              Text(request.reason,
                  style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
            const SizedBox(height: 8),

            // Requested scopes
            Wrap(
              spacing: 6,
              children: request.requestedScopes
                  .map((s) => _ScopeChip(scope: s))
                  .toList(),
            ),
            const SizedBox(height: 10),

            // Approve / Deny
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      svc.deny(rrn: robot.rrn, requestId: request.id),
                  child: const Text('Deny',
                      style: TextStyle(color: AppTheme.danger)),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: () => _approve(context, ref, svc),
                  child: const Text('Approve'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approve(
      BuildContext ctx, WidgetRef ref, ConsentService svc) async {
    // Default: grant exactly what was requested, 24h
    await svc.approve(
      rrn: robot.rrn,
      requestId: request.id,
      grantedScopes: request.requestedScopes,
      durationHours: request.durationHours,
    );
    if (ctx.mounted) {
      ScaffoldMessenger.of(ctx).showSnackBar(
        SnackBar(
            content: Text('Access granted to ${request.fromOwner}'),
            backgroundColor: AppTheme.online),
      );
    }
  }
}

class _PeerTile extends ConsumerWidget {
  final Robot robot;
  final Map<String, dynamic> peer;
  const _PeerTile({required this.robot, required this.peer});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final svc = ref.read(_consentSvcProvider);
    final cs = Theme.of(context).colorScheme;
    final scopes = List<String>.from(peer['granted_scopes'] ?? []);
    final expiresAt = peer['expires_at'] != null
        ? DateTime.tryParse(peer['expires_at'] as String)
        : null;

    return ListTile(
      dense: true,
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0),
      leading: const Icon(Icons.device_hub_outlined, size: 18),
      title: Text(peer['peer_owner'] as String? ?? 'Unknown',
          style: const TextStyle(fontSize: 13)),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
              spacing: 4,
              children: scopes.map((s) => _ScopeChip(scope: s)).toList()),
          if (expiresAt != null)
            Text('Expires ${timeago.format(expiresAt, allowFromNow: true)}',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.remove_circle_outline, size: 18, color: AppTheme.danger),
        tooltip: 'Revoke',
        onPressed: () async {
          final ok = await showDialog<bool>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Revoke consent?'),
              content: Text(
                  'Remove all access for ${peer['peer_owner']}? This takes effect immediately.'),
              actions: [
                TextButton(
                    onPressed: () => Navigator.pop(context, false),
                    child: const Text('Cancel')),
                FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppTheme.danger),
                    onPressed: () => Navigator.pop(context, true),
                    child: const Text('Revoke')),
              ],
            ),
          );
          if (ok == true) {
            await svc.revoke(
                rrn: robot.rrn,
                peerOwner: peer['peer_owner'] as String);
          }
        },
      ),
    );
  }
}

class _ScopeChip extends StatelessWidget {
  final String scope;
  const _ScopeChip({required this.scope});

  static const _colors = {
    'control': AppTheme.danger,
    'safety': AppTheme.estop,
    'chat': Colors.blue,
    'status': Colors.teal,
    'discover': Colors.grey,
    'transparency': Colors.purple,
  };

  @override
  Widget build(BuildContext context) {
    final color = _colors[scope] ?? Colors.grey;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Text(scope,
          style: TextStyle(
              fontSize: 10, color: color, fontWeight: FontWeight.w600)),
    );
  }
}
