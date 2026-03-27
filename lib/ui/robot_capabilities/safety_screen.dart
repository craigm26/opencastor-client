/// Safety (Protocol 66) sub-screen.
/// Route: /robot/:rrn/capabilities/safety
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../robot_detail/robot_detail_view_model.dart';
import 'capabilities_widgets.dart';

class SafetyScreen extends ConsumerWidget {
  final String rrn;
  const SafetyScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Safety')),
          body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Safety')),
              body: const Center(child: Text('Robot not found')));
        }
        return _SafetyView(robot: robot);
      },
    );
  }
}

class _SafetyView extends ConsumerWidget {
  final Robot robot;
  const _SafetyView({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: Text('Safety — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CapSection(
            title: 'Safety (Protocol 66)',
            icon: Icons.shield_outlined,
            rows: [
              CapabilityRow(
                label: 'ESTOP QoS',
                status: robot.supportsQos2
                    ? CapStatus.ok
                    : CapStatus.missing,
                description:
                    'Exactly-once delivery guarantee for ESTOP commands (GAP-11).',
              ),
              CapabilityRow(
                label: 'Replay Protection',
                status: robot.isRcanV15
                    ? CapStatus.ok
                    : CapStatus.missing,
                description:
                    'Prevents duplicate/replay command attacks via nonce cache (GAP-03).',
              ),
              CapabilityRow(
                label: robot.loaEnforcement
                    ? 'LoA Enforcement: ON'
                    : 'LoA Enforcement: OFF',
                status: robot.loaEnforcement
                    ? CapStatus.ok
                    : CapStatus.warning,
                description: robot.loaEnforcement
                    ? 'LoA policy enforced — min LoA ${robot.minLoaForControl} required (GAP-16).'
                    : 'LoA policy in log-only mode. Enable to enforce access control (GAP-16).',
                actionLabel:
                    robot.loaEnforcement ? null : 'Enable →',
                onAction: robot.loaEnforcement
                    ? null
                    : (ctx) => showLoaBottomSheet(ctx, rrn: robot.rrn, ref: ref),
              ),
            ],
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
