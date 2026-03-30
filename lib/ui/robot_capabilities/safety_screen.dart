/// Safety (Protocol 66) sub-screen.
/// Route: /robot/:rrn/capabilities/safety
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../robot_detail/robot_detail_view_model.dart';
import '../shared/error_view.dart';
import '../shared/empty_view.dart';
import '../shared/loading_view.dart';
import 'capabilities_widgets.dart';

class SafetyScreen extends ConsumerWidget {
  final String rrn;
  const SafetyScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () => const Scaffold(body: LoadingView()),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Safety')),
          body: ErrorView(error: e.toString())),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Safety')),
              body: const EmptyView(title: 'Robot not found'));
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
          const SizedBox(height: 16),
          _SafetyTelemetrySection(rrn: robot.rrn),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ── Safety telemetry section (Firestore stream) ───────────────────────────────

class _SafetyTelemetrySection extends StatelessWidget {
  final String rrn;
  const _SafetyTelemetrySection({required this.rrn});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('robots')
          .doc(rrn)
          .collection('telemetry')
          .doc('safety')
          .snapshots(),
      builder: (context, snap) {
        final safetyTelemetry =
            snap.data?.data() as Map<String, dynamic>? ?? {};
        final revocationLastCheckedS =
            safetyTelemetry['revocation_last_checked_s'] as int? ?? 0;
        final offlineMode =
            safetyTelemetry['offline_mode'] as bool? ?? false;
        final replayCacheSize =
            safetyTelemetry['replay_cache_size'] as int? ?? 0;

        return CapSection(
          title: 'Runtime Safety Telemetry',
          icon: Icons.monitor_heart_outlined,
          rows: [
            CapabilityRow(
              label: 'Revocation Poll',
              status: revocationLastCheckedS == 0
                  ? CapStatus.info
                  : revocationLastCheckedS < 60
                      ? CapStatus.ok
                      : CapStatus.warning,
              description: revocationLastCheckedS == 0
                  ? 'Not yet checked'
                  : 'Last checked: ${revocationLastCheckedS}s ago',
            ),
            CapabilityRow(
              label: 'Offline Mode',
              status: offlineMode ? CapStatus.warning : CapStatus.ok,
              description: offlineMode
                  ? 'Using cached credentials'
                  : 'Online — live credential validation',
            ),
            CapabilityRow(
              label: 'Replay Cache',
              status: CapStatus.info,
              description: '$replayCacheSize nonces cached',
            ),
          ],
        );
      },
    );
  }
}
