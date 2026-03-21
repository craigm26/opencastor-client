/// Identity & Registry sub-screen.
/// Route: /robot/:rrn/capabilities/identity
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/constants.dart';
import '../robot_detail/robot_detail_view_model.dart';
import 'capabilities_widgets.dart';

class IdentityScreen extends ConsumerWidget {
  final String rrn;
  const IdentityScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Identity & Registry')),
          body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Identity & Registry')),
              body: const Center(child: Text('Robot not found')));
        }
        return _IdentityView(robot: robot);
      },
    );
  }
}

class _IdentityView extends StatelessWidget {
  final Robot robot;
  const _IdentityView({required this.robot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('Identity — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CapSection(
            title: 'Identity & Registry',
            icon: Icons.badge_outlined,
            rows: [
              CapabilityRow(
                label: capRegistryTierLabel(robot.registryTier),
                status: CapStatus.ok,
                description:
                    'Registered in the ${robot.registryTier} tier registry.',
                actionLabel: 'Upgrade to Verified ↗',
                actionUrl: AppConstants.rrfOpencastorUrl,
              ),
              CapabilityRow(
                label: robot.rcanVersion != null
                    ? 'RCAN v${robot.rcanVersion}'
                    : 'RCAN version unknown',
                status: robot.rcanVersion != null
                    ? CapStatus.ok
                    : CapStatus.missing,
                description:
                    'RCAN protocol version reported by the bridge.',
              ),
              CapabilityRow(
                label: robot.rrn.isNotEmpty ? 'RRN assigned' : 'No RRN',
                status: robot.rrn.isNotEmpty
                    ? CapStatus.ok
                    : CapStatus.missing,
                description: robot.rrn.isNotEmpty
                    ? 'Robot Resource Name: ${robot.rrn}'
                    : 'Robot has no assigned RRN.',
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
