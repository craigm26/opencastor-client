/// Software Stack sub-screen.
/// Route: /robot/:rrn/capabilities/software
library;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../robot_detail/robot_detail_view_model.dart';
import '../robot_detail/slash_command_provider.dart';
import 'capabilities_widgets.dart';

class SoftwareScreen extends ConsumerWidget {
  final String rrn;
  const SoftwareScreen({super.key, required this.rrn});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final robotAsync = ref.watch(robotDetailProvider(rrn));
    return robotAsync.when(
      loading: () =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      error: (e, _) => Scaffold(
          appBar: AppBar(title: const Text('Software Stack')),
          body: Center(child: Text('Error: $e'))),
      data: (robot) {
        if (robot == null) {
          return Scaffold(
              appBar: AppBar(title: const Text('Software Stack')),
              body: const Center(child: Text('Robot not found')));
        }
        return _SoftwareView(robot: robot);
      },
    );
  }
}

class _SoftwareView extends ConsumerWidget {
  final Robot robot;
  const _SoftwareView({required this.robot});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final skillsAsync = ref.watch(slashCommandsProvider(robot.rrn));
    final t = robot.telemetry;

    final brainPrimary = t['brain_primary'] is Map
        ? Map<String, dynamic>.from(t['brain_primary'] as Map)
        : <String, dynamic>{};
    final activeModel = t['brain_active_model'] as String? ??
        brainPrimary['model'] as String? ??
        'Unknown';
    final provider = brainPrimary['provider'] as String? ?? 'unknown';
    final fallback = t['offline_fallback'] is Map
        ? Map<String, dynamic>.from(t['offline_fallback'] as Map)
        : <String, dynamic>{};
    final fallbackEnabled = fallback['enabled'] as bool? ?? false;
    final fallbackModel = fallback['fallback_model'] as String? ?? '';
    final fallbackProvider =
        fallback['fallback_provider'] as String? ?? '';
    final channels =
        capsAsList(t['channels_active']).whereType<String>().toList();
    final cameraModel = t['camera_model'] as String?;
    final version =
        robot.opencastorVersion ?? t['version'] as String?;
    final skills = (skillsAsync.value ?? [])
        .where((s) => s.group == 'Skills')
        .toList();

    final rows = <CapabilityRow>[
      CapabilityRow(
        label: activeModel,
        status:
            activeModel != 'Unknown' ? CapStatus.ok : CapStatus.info,
        description: 'Provider: $provider',
      ),
      if (fallbackEnabled && fallbackModel.isNotEmpty)
        CapabilityRow(
          label: '$fallbackModel (offline fallback)',
          status: CapStatus.ok,
          description: 'Provider: $fallbackProvider',
        ),
      CapabilityRow(
        label: channels.isNotEmpty
            ? channels.join(', ')
            : 'No active channels',
        status:
            channels.isNotEmpty ? CapStatus.ok : CapStatus.info,
        description: 'Communication channels',
      ),
      if (cameraModel != null && cameraModel != 'unknown')
        CapabilityRow(
          label: cameraModel,
          status: CapStatus.ok,
          description: 'Camera driver',
        ),
      if (version != null && version != 'unknown')
        CapabilityRow(
          label: 'OpenCastor $version',
          status: CapStatus.ok,
          description: 'Robot runtime version',
        ),
      CapabilityRow(
        label: skills.isEmpty
            ? 'No skills active'
            : '${skills.length} skill(s) active',
        status: skills.isEmpty ? CapStatus.info : CapStatus.ok,
        description: skills.isEmpty
            ? 'No skills enabled in RCAN config'
            : skills.map((s) => s.cmd).join(', '),
      ),
    ];

    return Scaffold(
      appBar: AppBar(title: Text('Software — ${robot.name}')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          CapSection(
            title: 'Software Stack',
            icon: Icons.layers_outlined,
            rows: rows,
          ),
          const SizedBox(height: 32),
        ],
      ),
    );
  }
}
