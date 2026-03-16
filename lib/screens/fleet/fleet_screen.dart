import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../app.dart' show authStateProvider;
import '../../models/robot.dart';
import '../../services/robot_service.dart';
import 'robot_card.dart';

final _robotServiceProvider = Provider((_) => RobotService());

/// StreamProvider that rebuilds whenever auth state changes.
/// If the user is not signed in, returns an empty stream (no Firestore query).
final fleetProvider = StreamProvider<List<Robot>>((ref) {
  // Watch authStateProvider so this rebuilds on sign-in / sign-out.
  final authAsync = ref.watch(authStateProvider);
  final user = authAsync.asData?.value;
  if (user == null) return const Stream.empty();
  return ref.read(_robotServiceProvider).watchFleet(user.uid);
});

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
            child: ListView.separated(
              padding: const EdgeInsets.all(16),
              itemCount: robots.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (ctx, i) {
                final robot = robots[i];
                final service = ref.read(_robotServiceProvider);

                return RobotCard(
                  robot: robot,
                  onTap: () => context.push('/robot/${robot.rrn}'),
                  onControl: robot.hasCapability(RobotCapability.control)
                      ? () => context.push('/robot/${robot.rrn}/control')
                      : null,
                  onEstop: () => service.sendEstop(robot.rrn),
                );
              },
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
          Text('Use the account button above or go to /login.',
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
          Text(
            'No robots yet',
            style: Theme.of(context).textTheme.titleLarge,
          ),
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
            const Icon(Icons.error_outline, size: 48, color: Colors.red),
            const SizedBox(height: 12),
            Text('Fleet unavailable', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(error, textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}
