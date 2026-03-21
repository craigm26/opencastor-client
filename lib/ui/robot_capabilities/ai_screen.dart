/// AI Capabilities sub-screen.
/// Route: /robot/:rrn/capabilities/ai
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../robot_detail/robot_detail_view_model.dart';
import 'capabilities_widgets.dart';

class AiCapabilitiesScreen extends ConsumerWidget {
  final String rrn;
  const AiCapabilitiesScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('AI Capabilities')),
          body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('AI Capabilities')),
              body: const Center(child: Text('Robot not found')));
        }
        return _AiView(robot: robot);
      },
    );
  }
}

class _AiView extends StatelessWidget {
  final Robot robot;
  const _AiView({required this.robot});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('AI Capabilities — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CapSection(
            title: 'AI Capabilities',
            icon: Icons.psychology_outlined,
            rows: [
              CapabilityRow(
                label: 'Delegation',
                status: robot.supportsDelegation ? CapStatus.ok : CapStatus.missing,
                description:
                    'Command delegation chains supported: human → cloud → robot (GAP-01).',
              ),
              CapabilityRow(
                label: 'Offline Mode',
                status: robot.offlineCapable ? CapStatus.ok : CapStatus.missing,
                description:
                    'Operates with cached credentials when disconnected (GAP-06).',
              ),
              CapabilityRow(
                label: robot.hasCapability(RobotCapability.vision)
                    ? 'Vision: enabled'
                    : 'Vision: not enabled',
                status: robot.hasCapability(RobotCapability.vision)
                    ? CapStatus.ok
                    : CapStatus.missing,
                description: 'Camera and visual perception capability (GAP-18).',
                actionLabel: robot.hasCapability(RobotCapability.vision) ? null : 'Enable →',
                onAction: robot.hasCapability(RobotCapability.vision)
                    ? null
                    : (ctx) => showVisionBottomSheet(ctx),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
