import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../data/models/robot.dart';
import 'fleet_view_model.dart'
    show authStateProvider, estopCommandProvider, fleetProvider;
import 'robot_card.dart';

class FleetScreen extends ConsumerWidget {
  const FleetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Fleet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle_outlined),
            tooltip: 'Account',
            onPressed: () => context.push('/account'),
          ),
        ],
      ),
      body: fleet.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (err, _) => _ErrorView(error: err.toString()),
        data: (robots) {
          if (robots.isEmpty) {
            final user = FirebaseAuth.instance.currentUser;
            return user == null ? const _SignInPrompt() : const _EmptyFleet();
          }
          return RefreshIndicator(
            onRefresh: () async => ref.invalidate(fleetProvider),
            child: _FleetList(
              robots: robots,
              onTap: (robot) => context.push('/robot/${robot.rrn}'),
              onControl: (robot) =>
                  context.push('/robot/${robot.rrn}/control'),
              onEstop: (robot) =>
                  ref.read(estopCommandProvider.notifier).send(robot.rrn),
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => context.push('/consent'),
        icon: const Icon(Icons.handshake_outlined),
        label: const Text('Manage Access'),
      ),
    );
  }
}

class _SignInPrompt extends StatelessWidget {
  const _SignInPrompt();
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Image.asset('assets/images/icon-128.png', width: 72, height: 72),
          const SizedBox(height: 20),
          Text('Sign in to view your fleet',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text('Use the account button above to sign in.',
              style: Theme.of(context).textTheme.bodyMedium,
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _EmptyFleet extends StatelessWidget {
  const _EmptyFleet();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.precision_manufacturing_outlined,
            size: 72,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(height: 16),
          Text('No robots yet',
              style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          Text(
            'Run  castor bridge  on a robot to add it to your fleet.',
            style: Theme.of(context).textTheme.bodyMedium,
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

// ── Fleet list with revocation + consent banners ──────────────────────────────

class _FleetList extends StatelessWidget {
  final List<Robot> robots;
  final void Function(Robot) onTap;
  final void Function(Robot) onControl;
  final Future<void> Function(Robot) onEstop;

  const _FleetList({
    required this.robots,
    required this.onTap,
    required this.onControl,
    required this.onEstop,
  });

  @override
  Widget build(BuildContext context) {
    final trainingRobots = robots
        .where((r) => r.telemetry['training_consent_required'] == true)
        .toList();
    final hasRevoked = robots.any((r) => r.isRevoked);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // EU AI Act training data consent banner (GAP-10)
        if (trainingRobots.isNotEmpty) ...[
          _TrainingConsentBanner(robots: trainingRobots),
          const SizedBox(height: 8),
        ],

        // Revocation summary banner
        if (hasRevoked) ...[
          const _RevocationSummaryBanner(),
          const SizedBox(height: 8),
        ],

        // Robot cards
        for (int i = 0; i < robots.length; i++) ...[
          if (i > 0) const SizedBox(height: 8),
          _RobotCardWithBadge(
            robot: robots[i],
            onTap: () => onTap(robots[i]),
            onControl: robots[i].hasCapability(RobotCapability.control) &&
                    !robots[i].isRevoked
                ? () => onControl(robots[i])
                : null,
            onEstop:
                robots[i].isOnline ? () => onEstop(robots[i]) : null,
          ),
        ],
      ],
    );
  }
}

/// RobotCard wrapper that overlays a revocation/suspension badge.
class _RobotCardWithBadge extends StatelessWidget {
  final Robot robot;
  final VoidCallback onTap;
  final VoidCallback? onControl;
  final Future<void> Function()? onEstop;

  const _RobotCardWithBadge({
    required this.robot,
    required this.onTap,
    this.onControl,
    this.onEstop,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RobotCard(
          robot: robot,
          onTap: onTap,
          onControl: onControl,
          onEstop: onEstop,
        ),
        if (robot.isRevoked)
          Positioned(
            top: 8,
            right: 8,
            child: Tooltip(
              message: 'Revoked robot — commands blocked',
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.red.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.block_outlined,
                        size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'REVOKED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        if (robot.isSuspended)
          Positioned(
            top: 8,
            right: 8,
            child: Tooltip(
              message: 'Suspended robot — commands temporarily blocked',
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.orange.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.pause_circle_outline,
                        size: 12, color: Colors.white),
                    SizedBox(width: 4),
                    Text(
                      'SUSPENDED',
                      style: TextStyle(
                        fontSize: 10,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// Banner shown when one or more fleet robots are revoked.
class _RevocationSummaryBanner extends StatelessWidget {
  const _RevocationSummaryBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_outlined,
              size: 16, color: Colors.red),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'One or more robots have been revoked. '
              'Tap a robot for details.',
              style: TextStyle(
                  fontSize: 12,
                  color: Colors.red.shade300),
            ),
          ),
        ],
      ),
    );
  }
}

/// EU AI Act compliance banner (GAP-10) shown when a robot has
/// training_consent_required == true in its telemetry/config.
class _TrainingConsentBanner extends StatelessWidget {
  final List<Robot> robots;
  const _TrainingConsentBanner({required this.robots});

  @override
  Widget build(BuildContext context) {
    final names = robots.map((r) => r.name).join(', ');
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.privacy_tip_outlined,
              size: 16, color: Colors.amber),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Training data consent required',
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: Colors.amber),
                ),
                Text(
                  '$names collects training data. '
                  'Review and manage consent →',
                  style: TextStyle(
                      fontSize: 11,
                      color: Colors.amber.withOpacity(0.8)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  final String error;
  const _ErrorView({required this.error});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 48),
            const SizedBox(height: 16),
            Text('Fleet unavailable',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error,
                style: Theme.of(context).textTheme.bodySmall,
                textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
