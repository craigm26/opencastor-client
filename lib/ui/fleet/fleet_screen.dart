import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shimmer/shimmer.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/constants.dart';
import '../../data/models/robot.dart';
import 'fleet_view_model.dart'
    show estopCommandProvider, fleetProvider;
import 'robot_card.dart';

/// Maximum robots a free account may register. Matches MAX_ROBOTS in
/// functions/src/registration.ts — update both when pricing launches.
const int _kMaxRobots = 2;

class FleetScreen extends ConsumerWidget {
  const FleetScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fleet = ref.watch(fleetProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('OpenCastor Fleet'),
        actions: [
          IconButton(
            icon: const Icon(Icons.info_outline),
            tooltip: 'Fleet Docs',
            onPressed: () => launchUrl(Uri.parse(AppConstants.docsRoot)),
          ),
          // Profile avatar — shows photo if signed in, fallback icon if not
          _ProfileAvatarButton(),
        ],
      ),
      body: Column(
        children: [
          // ── Summary strip ─────────────────────────────────────────────
          fleet.whenData((robots) => robots).valueOrNull != null
              ? _SummaryStrip(
                  robots: fleet.value!,
                  onRefresh: () => ref.invalidate(fleetProvider),
                )
              : const SizedBox.shrink(),

          // ── Main content with AnimatedSwitcher ────────────────────────
          Expanded(
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              child: fleet.when(
                loading: () => const _ShimmerFleetList(),
                error: (err, _) => _ErrorView(error: err.toString()),
                data: (robots) {
                  if (robots.isEmpty) {
                    final user = FirebaseAuth.instance.currentUser;
                    return user == null
                        ? const _SignInPrompt()
                        : const _EmptyFleet();
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
            ),
          ),
        ],
      ),
      floatingActionButton: fleet.when(
        loading: () => FloatingActionButton.extended(
          onPressed: () => context.push('/consent'),
          icon: const Icon(Icons.handshake_outlined),
          label: const Text('Manage Access'),
        ),
        error: (_, __) => FloatingActionButton.extended(
          onPressed: () => context.push('/consent'),
          icon: const Icon(Icons.handshake_outlined),
          label: const Text('Manage Access'),
        ),
        data: (robots) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // Add Robot button — locked when fleet limit reached
            _AddRobotFab(robotCount: robots.length),
            const SizedBox(height: 12),
            FloatingActionButton.extended(
              heroTag: 'manageAccess',
              onPressed: () => context.push('/consent'),
              icon: const Icon(Icons.handshake_outlined),
              label: const Text('Manage Access'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Add Robot FAB with fleet-limit enforcement ────────────────────────────────

/// FAB that links to the robot setup docs, but shows an upgrade prompt
/// when the user has already reached [_kMaxRobots].
class _AddRobotFab extends StatelessWidget {
  final int robotCount;
  const _AddRobotFab({required this.robotCount});

  @override
  Widget build(BuildContext context) {
    final atLimit = robotCount >= _kMaxRobots;
    return FloatingActionButton.extended(
      heroTag: 'addRobot',
      backgroundColor: atLimit
          ? Theme.of(context).colorScheme.surfaceContainerHighest
          : null,
      foregroundColor: atLimit
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : null,
      onPressed: () {
        if (atLimit) {
          _showFleetLimitDialog(context);
        } else {
          launchUrl(Uri.parse(AppConstants.docsRoot));
        }
      },
      icon: Icon(atLimit ? Icons.lock_outline : Icons.add_circle_outline),
      label: Text(atLimit ? 'Fleet limit reached' : 'Add Robot'),
    );
  }
}

void _showFleetLimitDialog(BuildContext context) {
  showDialog<void>(
    context: context,
    builder: (_) => AlertDialog(
      title: const Text('Fleet limit reached'),
      content: const Text(
        'Free accounts support up to $_kMaxRobots robots.\n\n'
        'Pricing plans are coming soon — contact us to get early access '
        'to expanded fleets.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('OK'),
        ),
        TextButton(
          onPressed: () => launchUrl(
            Uri.parse(
              'mailto:hello@opencastor.com?subject=Fleet%20upgrade',
            ),
          ),
          child: const Text('Contact Us'),
        ),
      ],
    ),
  );
}

// ── Summary strip ─────────────────────────────────────────────────────────────

class _SummaryStrip extends StatelessWidget {
  final List<Robot> robots;
  final VoidCallback onRefresh;
  const _SummaryStrip({required this.robots, required this.onRefresh});

  @override
  Widget build(BuildContext context) {
    final onlineCount = robots.where((r) => r.isOnline).length;
    final cs = Theme.of(context).colorScheme;
    return Container(
      color: cs.surfaceContainerLow,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          Icon(Icons.circle, size: 8,
              color: onlineCount > 0 ? const Color(0xFF146C2E) : cs.outline),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Online: $onlineCount / ${robots.length}',
              style: Theme.of(context).textTheme.labelMedium,
            ),
          ),
          Semantics(
            label: 'Refresh fleet',
            button: true,
            child: Tooltip(
              message: 'Refresh',
              child: InkWell(
                onTap: onRefresh,
                borderRadius: BorderRadius.circular(16),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(Icons.refresh, size: 18, color: cs.onSurfaceVariant),
                ),
              ),
            ),
          ),
        ],
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
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: cs.primaryContainer,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.precision_manufacturing_outlined,
                size: 48,
                color: cs.onPrimaryContainer,
              ),
            ),
            const SizedBox(height: 24),
            Text('No robots yet',
                style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(
              'Run  castor bridge  on a robot to add it to your fleet.',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: () => launchUrl(Uri.parse(AppConstants.docsRoot)),
              icon: const Icon(Icons.open_in_new, size: 16),
              label: const Text('Add your first robot'),
            ),
          ],
        ),
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

        // Responsive robot grid
        LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final cols = width >= 900 ? 3 : width >= 600 ? 2 : 1;
            if (cols == 1) {
              return Column(
                children: [
                  for (int i = 0; i < robots.length; i++) ...[
                    if (i > 0) const SizedBox(height: 8),
                    _RobotCardWithBadge(
                      robot: robots[i],
                      onTap: () => onTap(robots[i]),
                      onControl: robots[i].hasCapability(RobotCapability.control) &&
                              !robots[i].isRevoked
                          ? () => onControl(robots[i])
                          : null,
                      onEstop: robots[i].isOnline
                          ? () => onEstop(robots[i])
                          : null,
                    ),
                  ],
                ],
              );
            }
            return GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: cols,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
                childAspectRatio: 1.8,
              ),
              itemCount: robots.length,
              itemBuilder: (_, i) => _RobotCardWithBadge(
                robot: robots[i],
                onTap: () => onTap(robots[i]),
                onControl: robots[i].hasCapability(RobotCapability.control) &&
                        !robots[i].isRevoked
                    ? () => onControl(robots[i])
                    : null,
                onEstop:
                    robots[i].isOnline ? () => onEstop(robots[i]) : null,
              ),
            );
          },
        ),
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

// ── Shimmer loading skeleton ──────────────────────────────────────────────────

class _ShimmerFleetList extends StatelessWidget {
  const _ShimmerFleetList();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListView.separated(
      padding: const EdgeInsets.all(16),
      itemCount: 3,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (_, __) => Shimmer.fromColors(
        baseColor: cs.surfaceContainerLow,
        highlightColor: cs.surfaceContainer,
        child: Card(
          child: SizedBox(height: 120),
        ),
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

// ── Profile avatar button ─────────────────────────────────────────────────────

class _ProfileAvatarButton extends StatelessWidget {
  const _ProfileAvatarButton();

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final cs = Theme.of(context).colorScheme;

    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => context.push('/account'),
        child: Tooltip(
          message: user?.displayName ?? user?.email ?? 'Account',
          child: CircleAvatar(
            radius: 16,
            backgroundColor: cs.primaryContainer,
            backgroundImage: user?.photoURL != null
                ? NetworkImage(user!.photoURL!)
                : null,
            child: user?.photoURL == null
                ? Text(
                    _initials(user?.displayName ?? user?.email),
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      color: cs.onPrimaryContainer,
                    ),
                  )
                : null,
          ),
        ),
      ),
    );
  }

  String _initials(String? name) {
    if (name == null || name.isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
  }
}
